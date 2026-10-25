import Foundation
import SwiftUI
import HuazhouCore
import UniformTypeIdentifiers

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "标准地图"
        case .satellite: return "卫星影像"
        case .hybrid: return "卫星混合"
        }
    }
}

/// 国内常用第三方瓦片源预设（填进自定义瓦片模板）
struct TilePreset: Identifiable {
    let id = UUID()
    let name: String
    let template: String
    let needsCorrection: Bool

    static let all: [TilePreset] = [
        TilePreset(name: "高德 矢量", template: "https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}", needsCorrection: true),
        TilePreset(name: "高德 影像", template: "https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}", needsCorrection: true),
        TilePreset(name: "腾讯 矢量", template: "https://rt0.map.gtimg.com/tile?z={z}&x={x}&y={-y}&type=vector&styleid=3", needsCorrection: true),
        TilePreset(name: "天地图 矢量", template: "https://t0.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的KEY", needsCorrection: false),
        TilePreset(name: "OSM", template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", needsCorrection: false),
        TilePreset(name: "本地瓦片服务", template: "https://sydt.hainasi.eu.org/{z}/{x}/{y}.png", needsCorrection: false),
    ]
}

enum SidebarTab: Int, CaseIterable, Identifiable {
    case points
    case segments
    case settings

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .points: return "点位"
        case .segments: return "分段"
        case .settings: return "设置"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var project = SurveyProject()
    @Published var selection: UUID?
    @Published var addMode = true
    @Published var activeKind: ObjectKind = .pole
    @Published var mapStyle: MapStyleChoice = .standard
    @Published var useCustomTiles = false
    @Published var customTileURL = "https://sydt.hainasi.eu.org/{z}/{x}/{y}.png"
    @Published var centralMeridianText = ""
    @Published var poleRadius = 0.5
    @Published var textHeight = 1.5
    @Published var showSegmentLength = true
    @Published var sidebarTab: SidebarTab = .points
    @Published var message = "点击地图打点，或 ⌘⇧P 手动输入坐标"
    @Published var showManualEntry = false

    private(set) var currentFileURL: URL?

    var chain: ChainResult {
        ChainBuilder.build(project.points, mode: project.chainMode)
    }

    var projection: ProjectionSetting {
        let meridian = Double(centralMeridianText.trimmingCharacters(in: .whitespaces))
        return ProjectionSetting(kind: project.projection.kind, centralMeridian: meridian, origin: project.projection.origin)
    }

    var projector: Projector? {
        guard let first = project.points.first else { return nil }
        return Projector(setting: projection, reference: first.coordinate)
    }

    var selectedPoint: SurveyPoint? {
        guard let selection else { return nil }
        return project.points.first { $0.id == selection }
    }

    /// 闭合环面积（≥3 点），平方米
    var polygonArea: Double? {
        let ordered = chain.orderedPoints
        guard ordered.count >= 3 else { return nil }
        return Geometry.polygonArea(ordered.map(\.coordinate))
    }

    /// 显示用坐标：开启纠偏时把 WGS84 转成 GCJ-02 以对齐国内底图
    func displayCoordinate(_ coordinate: LatLon) -> LatLon {
        project.applyGCJCorrection ? CoordinateCorrection.wgs84ToGCJ02(coordinate) : coordinate
    }

    /// 反向：把底图上取到的坐标还原成 WGS84 入库
    func storageCoordinate(_ coordinate: LatLon) -> LatLon {
        project.applyGCJCorrection ? CoordinateCorrection.gcj02ToWGS84(coordinate) : coordinate
    }

    // MARK: - 编辑

    func addPoint(at coordinate: LatLon, kind: ObjectKind? = nil) {
        let type = kind ?? activeKind
        let point = SurveyPoint(name: project.nextPointName(for: type), coordinate: coordinate, kind: type)
        project.points.append(point)
        selection = point.id
        message = String(format: "已添加 %@ %@（%.6f, %.6f）", type.displayName, point.name, coordinate.latitude, coordinate.longitude)
    }

    func addPointManually(name: String, latitude: Double, longitude: Double, kind: ObjectKind, note: String) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            message = "经纬度超出范围"
            return
        }
        var point = SurveyPoint(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? project.nextPointName(for: kind) : name,
            coordinate: LatLon(latitude: latitude, longitude: longitude),
            note: note,
            kind: kind
        )
        if project.points.contains(where: { $0.name == point.name }) {
            point.name = project.nextPointName(for: kind)
        }
        project.points.append(point)
        selection = point.id
        message = "已手动添加 \(point.name)"
    }

    func movePoint(id: UUID, to coordinate: LatLon) {
        guard let index = project.points.firstIndex(where: { $0.id == id }) else { return }
        project.points[index].coordinate = coordinate
        message = String(format: "已移动 %@ 到 %.6f, %.6f", project.points[index].name, coordinate.latitude, coordinate.longitude)
    }

    func deleteSelected() {
        guard let selection, let index = project.points.firstIndex(where: { $0.id == selection }) else { return }
        let removed = project.points.remove(at: index)
        self.selection = nil
        message = "已删除 \(removed.name)"
    }

    func renamePoint(id: UUID, to name: String) {
        guard let index = project.points.firstIndex(where: { $0.id == id }) else { return }
        project.points[index].name = name
    }

    func setKind(id: UUID, kind: ObjectKind) {
        guard let index = project.points.firstIndex(where: { $0.id == id }) else { return }
        project.points[index].kind = kind
    }

    func clearAll() {
        project = SurveyProject()
        selection = nil
        currentFileURL = nil
        message = "已新建空工程"
    }

    // MARK: - 文件

    func newProject() { clearAll() }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            project = try SurveyProject.load(from: Data(contentsOf: url))
            currentFileURL = url
            selection = nil
            centralMeridianText = project.projection.centralMeridian.map { String(format: "%g", $0) } ?? ""
            message = "已打开 \(url.lastPathComponent)（\(project.points.count) 点）"
        } catch {
            message = "打开失败：\(error.localizedDescription)"
        }
    }

    func saveProject() {
        if let url = currentFileURL { write(to: url) } else { saveProjectAs() }
    }

    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = project.name + ".hzmap"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
        currentFileURL = url
    }

    private func write(to url: URL) {
        do {
            try project.jsonData().write(to: url)
            message = "已保存 \(url.lastPathComponent)"
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 导入

    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let points = try CSVImporter.parse(data: Data(contentsOf: url), defaultKind: activeKind)
            mergeImported(points, source: url.lastPathComponent)
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    func importKML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "kml") ?? .xml, .xml]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let points = try KMLImporter.parse(data: Data(contentsOf: url), defaultKind: activeKind)
            mergeImported(points, source: url.lastPathComponent)
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    private func mergeImported(_ points: [SurveyPoint], source: String) {
        var incoming = points
        // 避免点名重复
        for i in incoming.indices where project.points.contains(where: { $0.name == incoming[i].name }) {
            incoming[i].name = project.nextPointName(for: incoming[i].kind)
        }
        project.points.append(contentsOf: incoming)
        selection = incoming.last?.id
        message = "从 \(source) 导入 \(incoming.count) 个点"
    }

    // MARK: - 导出

    var dxfOptions: DXFExportOptions {
        DXFExportOptions(
            projection: projection,
            poleRadius: poleRadius,
            textHeight: textHeight,
            showPointName: true,
            showSegmentLength: showSegmentLength
        )
    }

    func exportDXF() {
        guard !project.points.isEmpty else { message = "没有点位可导出"; return }
        guard let url = saveURL(name: project.name + ".dxf", type: UTType(filenameExtension: "dxf")) else { return }
        do {
            try DXFWriter.writeFile(points: project.points, chain: chain, options: dxfOptions, to: url)
            message = "已导出 DXF：\(url.lastPathComponent)（\(chain.pointCount) 点 / \(String(format: "%.1f", chain.totalLength)) m）"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    func exportCSV() {
        guard !project.points.isEmpty else { message = "没有点位可导出"; return }
        guard let url = saveURL(name: project.name + ".csv", type: .commaSeparatedText) else { return }
        do {
            try CSVWriter.writeFile(points: project.points, chain: chain, projection: projection, to: url)
            message = "已导出 CSV：\(url.lastPathComponent)"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    func exportKML() {
        guard !project.points.isEmpty else { message = "没有点位可导出"; return }
        guard let url = saveURL(name: project.name + ".kml", type: UTType(filenameExtension: "kml")) else { return }
        do {
            try KMLWriter.writeFile(points: project.points, chain: chain, documentName: project.name, to: url)
            message = "已导出 KML：\(url.lastPathComponent)"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    func exportGPX() {
        guard !project.points.isEmpty else { message = "没有点位可导出"; return }
        guard let url = saveURL(name: project.name + ".gpx", type: UTType(filenameExtension: "gpx")) else { return }
        do {
            try GPXWriter.writeFile(points: project.points, chain: chain, name: project.name, to: url)
            message = "已导出 GPX：\(url.lastPathComponent)"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func saveURL(name: String, type: UTType?) -> URL? {
        let panel = NSSavePanel()
        if let type { panel.allowedContentTypes = [type] }
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private static var projectType: UTType {
        UTType(filenameExtension: "hzmap") ?? .json
    }
}
