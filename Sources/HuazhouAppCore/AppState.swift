import Foundation
import SwiftUI
import AppKit
import HuazhouCore
import UniformTypeIdentifiers

public enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "标准地图"
        case .satellite: return "卫星影像"
        case .hybrid: return "卫星混合"
        }
    }
}

/// 国内常用第三方瓦片源预设（填进自定义瓦片模板）
public struct TilePreset: Identifiable {
    public let id = UUID()
    public let name: String
    public let template: String
    public let needsCorrection: Bool

    public init(name: String, template: String, needsCorrection: Bool) {
        self.name = name
        self.template = template
        self.needsCorrection = needsCorrection
    }

    public static let all: [TilePreset] = [
        TilePreset(name: "高德 矢量", template: "https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}", needsCorrection: true),
        TilePreset(name: "高德 影像", template: "https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}", needsCorrection: true),
        TilePreset(name: "腾讯 矢量", template: "https://rt0.map.gtimg.com/tile?z={z}&x={x}&y={-y}&type=vector&styleid=3", needsCorrection: true),
        TilePreset(name: "天地图 矢量", template: "https://t0.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的KEY", needsCorrection: false),
        TilePreset(name: "OSM", template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", needsCorrection: false),
        TilePreset(name: "本地瓦片服务", template: "https://sydt.hainasi.eu.org/{z}/{x}/{y}.png", needsCorrection: false),
    ]
}

public enum SidebarTab: Int, CaseIterable, Identifiable {
    case points
    case segments
    case settings

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .points: return "点位"
        case .segments: return "分段"
        case .settings: return "设置"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    /// 任何改动都会触发链路重算（只算一次，界面多次读取不再重算）
    @Published public var project: SurveyProject {
        didSet { rebuildChain() }
    }
    /// 缓存后的成链结果。300 点最近邻成链约 10 ms，界面一次渲染会读七八次，必须缓存。
    @Published public private(set) var chain: ChainResult
    @Published public var selection: UUID?
    @Published public var addMode = true
    @Published public var activeKind: ObjectKind = .pole
    @Published public var mapStyle: MapStyleChoice = .standard
    @Published public var useCustomTiles = false
    @Published public var customTileURL = "https://sydt.hainasi.eu.org/{z}/{x}/{y}.png"
    @Published public var poleRadius = 0.5
    @Published public var textHeight = 1.5
    @Published public var showSegmentLength = true
    @Published public var sidebarTab: SidebarTab = .points
    @Published public var message = "点击地图打点，或 ⌘⇧P 手动输入坐标"
    @Published public var showManualEntry = false

    public private(set) var currentFileURL: URL?

    public init(project: SurveyProject = SurveyProject()) {
        self.project = project
        self.chain = ChainBuilder.build(project.points, mode: project.chainMode)
    }

    private func rebuildChain() {
        chain = ChainBuilder.build(project.points, mode: project.chainMode)
    }

    /// 中央子午线直接读写工程设置，避免"界面输入了、保存时丢失"
    public var centralMeridianText: String {
        get { project.projection.centralMeridian.map { String(format: "%g", $0) } ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            project.projection.centralMeridian = Double(trimmed)
        }
    }

    public var projection: ProjectionSetting { project.projection }

    public var projector: Projector? {
        guard let first = project.points.first else { return nil }
        return Projector(setting: project.projection, reference: first.coordinate)
    }

    public var selectedPoint: SurveyPoint? {
        guard let selection else { return nil }
        return project.points.first { $0.id == selection }
    }

    /// 闭合环面积（≥3 点），平方米
    public var polygonArea: Double? {
        let ordered = chain.orderedPoints
        guard ordered.count >= 3 else { return nil }
        return Geometry.polygonArea(ordered.map(\.coordinate))
    }

    /// 显示用坐标：开启纠偏时把 WGS84 转成 GCJ-02 以对齐国内底图
    public func displayCoordinate(_ coordinate: LatLon) -> LatLon {
        project.applyGCJCorrection ? CoordinateCorrection.wgs84ToGCJ02(coordinate) : coordinate
    }

    /// 反向：把底图上取到的坐标还原成 WGS84 入库
    public func storageCoordinate(_ coordinate: LatLon) -> LatLon {
        project.applyGCJCorrection ? CoordinateCorrection.gcj02ToWGS84(coordinate) : coordinate
    }

    // MARK: - 编辑

    public func addPoint(at coordinate: LatLon, kind: ObjectKind? = nil) {
        let type = kind ?? activeKind
        let point = SurveyPoint(name: project.nextPointName(for: type), coordinate: coordinate, kind: type)
        project.points.append(point)
        selection = point.id
        message = String(format: "已添加 %@ %@（%.6f, %.6f）", type.displayName, point.name, coordinate.latitude, coordinate.longitude)
    }

    @discardableResult
    public func addPointManually(name: String, latitude: Double, longitude: Double, kind: ObjectKind, note: String) -> Bool {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            message = "经纬度超出范围"
            return false
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
        return true
    }

    public func movePoint(id: UUID, to coordinate: LatLon) {
        guard let index = project.points.firstIndex(where: { $0.id == id }) else { return }
        project.points[index].coordinate = coordinate
        message = String(format: "已移动 %@ 到 %.6f, %.6f", project.points[index].name, coordinate.latitude, coordinate.longitude)
    }

    public func deleteSelected() {
        guard let selection, let index = project.points.firstIndex(where: { $0.id == selection }) else { return }
        let removed = project.points.remove(at: index)
        self.selection = nil
        message = "已删除 \(removed.name)"
    }

    public func renamePoint(id: UUID, to name: String) {
        guard let index = project.points.firstIndex(where: { $0.id == id }) else { return }
        project.points[index].name = name
    }

    public func setKind(id: UUID, kind: ObjectKind) {
        guard let index = project.points.firstIndex(where: { $0.id == id }) else { return }
        project.points[index].kind = kind
    }

    public func clearAll() {
        project = SurveyProject()
        selection = nil
        currentFileURL = nil
        activeKind = .pole
        message = "已新建空工程"
    }

    public func newProject() { clearAll() }

    /// 从命令行参数打开工程（终端里 `HuazhouMap 工程.hzmap` 启动即载入）
    public func loadStartupProjectFromCommandLine() {
        guard currentFileURL == nil else { return }
        for argument in CommandLine.arguments.dropFirst() where argument.hasSuffix(".hzmap") {
            let url = URL(fileURLWithPath: argument)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { try load(from: url) } catch { message = "启动加载失败：\(error.localizedDescription)" }
            return
        }
    }

    // MARK: - 工程文件（可测核心，面板只做外壳）

    public func save(to url: URL) throws {
        try project.jsonData().write(to: url)
        currentFileURL = url
        message = "已保存 \(url.lastPathComponent)"
    }

    public func load(from url: URL) throws {
        project = try SurveyProject.load(from: Data(contentsOf: url))
        currentFileURL = url
        selection = nil
        message = "已打开 \(url.lastPathComponent)（\(project.points.count) 点）"
    }

    // MARK: - 导入（可测）

    public func importCSV(data: Data, sourceName: String = "CSV") throws {
        let points = try CSVImporter.parse(data: data, defaultKind: activeKind)
        mergeImported(points, source: sourceName)
    }

    public func importKML(data: Data, sourceName: String = "KML") throws {
        let points = try KMLImporter.parse(data: data, defaultKind: activeKind)
        mergeImported(points, source: sourceName)
    }

    private func mergeImported(_ points: [SurveyPoint], source: String) {
        var incoming = points
        for i in incoming.indices where project.points.contains(where: { $0.name == incoming[i].name }) {
            incoming[i].name = project.nextPointName(for: incoming[i].kind)
        }
        project.points.append(contentsOf: incoming)
        selection = incoming.last?.id
        message = "从 \(source) 导入 \(incoming.count) 个点"
    }

    // MARK: - 导出（可测）

    public var dxfOptions: DXFExportOptions {
        DXFExportOptions(
            projection: projection,
            poleRadius: poleRadius,
            textHeight: textHeight,
            showPointName: true,
            showSegmentLength: showSegmentLength
        )
    }

    public func exportDXF(to url: URL) throws {
        try DXFWriter.writeFile(points: project.points, chain: chain, options: dxfOptions, to: url)
        message = "已导出 DXF：\(url.lastPathComponent)（\(chain.pointCount) 点 / \(String(format: "%.1f", chain.totalLength)) m）"
    }

    public func exportCSV(to url: URL) throws {
        try CSVWriter.writeFile(points: project.points, chain: chain, projection: projection, to: url)
        message = "已导出 CSV：\(url.lastPathComponent)"
    }

    public func exportKML(to url: URL) throws {
        try KMLWriter.writeFile(points: project.points, chain: chain, documentName: project.name, to: url)
        message = "已导出 KML：\(url.lastPathComponent)"
    }

    public func exportGPX(to url: URL) throws {
        try GPXWriter.writeFile(points: project.points, chain: chain, name: project.name, to: url)
        message = "已导出 GPX：\(url.lastPathComponent)"
    }

    // MARK: - 面板外壳

    public func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try load(from: url) } catch { message = "打开失败：\(error.localizedDescription)" }
    }

    public func saveProject() {
        if let url = currentFileURL {
            do { try save(to: url) } catch { message = "保存失败：\(error.localizedDescription)" }
        } else {
            saveProjectAs()
        }
    }

    public func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = project.name + ".hzmap"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try save(to: url) } catch { message = "保存失败：\(error.localizedDescription)" }
    }

    public func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try importCSV(data: Data(contentsOf: url), sourceName: url.lastPathComponent) }
        catch { message = "导入失败：\(error.localizedDescription)" }
    }

    public func importKML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "kml") ?? .xml, .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try importKML(data: Data(contentsOf: url), sourceName: url.lastPathComponent) }
        catch { message = "导入失败：\(error.localizedDescription)" }
    }

    public func exportDXF() {
        guard requirePoints() else { return }
        guard let url = saveURL(name: project.name + ".dxf", type: UTType(filenameExtension: "dxf")) else { return }
        do { try exportDXF(to: url) } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    public func exportCSV() {
        guard requirePoints() else { return }
        guard let url = saveURL(name: project.name + ".csv", type: .commaSeparatedText) else { return }
        do { try exportCSV(to: url) } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    public func exportKML() {
        guard requirePoints() else { return }
        guard let url = saveURL(name: project.name + ".kml", type: UTType(filenameExtension: "kml")) else { return }
        do { try exportKML(to: url) } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    public func exportGPX() {
        guard requirePoints() else { return }
        guard let url = saveURL(name: project.name + ".gpx", type: UTType(filenameExtension: "gpx")) else { return }
        do { try exportGPX(to: url) } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    private func requirePoints() -> Bool {
        guard project.points.isEmpty else { return true }
        message = "没有点位可导出"
        return false
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
