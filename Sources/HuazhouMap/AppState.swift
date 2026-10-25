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
    @Published var mapStyle: MapStyleChoice = .standard
    @Published var useCustomTiles = false
    @Published var customTileURL = "https://sydt.hainasi.eu.org/{z}/{x}/{y}.png"
    @Published var centralMeridianText = ""
    @Published var poleRadius = 0.5
    @Published var textHeight = 1.5
    @Published var showSegmentLength = true
    @Published var sidebarTab: SidebarTab = .points
    @Published var message = "点击地图开始打点"

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

    // MARK: - 编辑

    func addPoint(at coordinate: LatLon) {
        let point = SurveyPoint(name: project.nextPointName(), coordinate: coordinate)
        project.points.append(point)
        selection = point.id
        message = String(format: "已添加 %@（%.4f, %.4f）", point.name, coordinate.latitude, coordinate.longitude)
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

    func clearAll() {
        project = SurveyProject()
        selection = nil
        currentFileURL = nil
        message = "已新建空工程"
    }

    // MARK: - 文件

    func newProject() {
        clearAll()
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            project = try SurveyProject.load(from: data)
            currentFileURL = url
            selection = nil
            centralMeridianText = project.projection.centralMeridian.map { String(format: "%g", $0) } ?? ""
            message = "已打开 \(url.lastPathComponent)"
        } catch {
            message = "打开失败：\(error.localizedDescription)"
        }
    }

    func saveProject() {
        if let url = currentFileURL {
            write(to: url)
        } else {
            saveProjectAs()
        }
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
        guard !project.points.isEmpty else {
            message = "没有点位可导出"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .data]
        panel.nameFieldStringValue = project.name + ".dxf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DXFWriter.writeFile(points: project.points, chain: chain, options: dxfOptions, to: url)
            message = "已导出 DXF：\(url.lastPathComponent)（\(chain.pointCount) 点 / \(String(format: "%.1f", chain.totalLength)) m）"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    func exportCSV() {
        guard !project.points.isEmpty else {
            message = "没有点位可导出"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = project.name + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVWriter.writeFile(points: project.points, chain: chain, projection: projection, to: url)
            message = "已导出 CSV：\(url.lastPathComponent)"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private static var projectType: UTType {
        UTType(filenameExtension: "hzmap") ?? .json
    }
}
