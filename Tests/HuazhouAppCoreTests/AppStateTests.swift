import Testing
import Foundation
@testable import HuazhouAppCore
import HuazhouCore

@MainActor
@Suite("应用状态机（端到端）")
struct AppStateTests {

    private func makeState(prefix: String = "G") -> AppState {
        let state = AppState()
        state.project.name = "测试工程"
        return state
    }

    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hztest-\(UUID().uuidString).\(ext)")
    }

    // MARK: 打点

    @Test("按类型自动命名：电杆 G / 人孔 R，并自动选中新点")
    func addPointByKind() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.1301, longitude: 114.0814), kind: .pole)
        state.addPoint(at: LatLon(latitude: 32.1310, longitude: 114.0820), kind: .manhole)

        #expect(state.project.points.count == 2)
        #expect(state.project.points[0].name == "G001")
        #expect(state.project.points[1].name == "R001")
        #expect(state.selection == state.project.points[1].id)
        #expect(state.selectedPoint?.name == "R001")
    }

    @Test("使用 activeKind 打点")
    func addPointUsesActiveKind() {
        let state = makeState()
        state.activeKind = .joint
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))
        #expect(state.project.points[0].kind == .joint)
        #expect(state.project.points[0].name == "J001")
    }

    // MARK: 手动输入

    @Test("手动输入越界经纬度被拒绝")
    func manualEntryRejectsInvalid() {
        let state = makeState()
        #expect(state.addPointManually(name: "X", latitude: 200, longitude: 114, kind: .pole, note: "") == false)
        #expect(state.project.points.isEmpty)
        #expect(state.message.contains("超出范围"))
    }

    @Test("手动输入重名自动改号，空名自动编号")
    func manualEntryDedupesName() {
        let state = makeState()
        state.addPointManually(name: "G001", latitude: 32.13, longitude: 114.08, kind: .pole, note: "")
        state.addPointManually(name: "G001", latitude: 32.14, longitude: 114.09, kind: .pole, note: "")
        state.addPointManually(name: "  ", latitude: 32.15, longitude: 114.10, kind: .pole, note: "")

        let names = state.project.points.map(\.name)
        #expect(names.count == 3)
        #expect(Set(names).count == 3, "点名必须唯一，实际：\(names)")
    }

    // MARK: 编辑

    @Test("移动点位后链路长度随之变化")
    func movePointChangesLength() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08), kind: .pole)
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.09), kind: .pole)
        let before = state.chain.totalLength

        let id = state.project.points[1].id
        state.movePoint(id: id, to: LatLon(latitude: 32.13, longitude: 114.18))
        let after = state.chain.totalLength

        #expect(after > before * 1.8)
        #expect(abs(after - 9435.9) < 20)
    }

    @Test("删除选中点后清空选中状态")
    func deleteSelected() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))
        state.addPoint(at: LatLon(latitude: 32.14, longitude: 114.09))
        state.deleteSelected()
        #expect(state.project.points.count == 1)
        #expect(state.selection == nil)
    }

    @Test("切换对象类型")
    func changeKind() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))
        let id = state.project.points[0].id
        state.setKind(id: id, kind: .station)
        #expect(state.project.points[0].kind == .station)
    }

    @Test("清空工程会重置类型与中央子午线")
    func clearAllResetsEverything() {
        let state = makeState()
        state.activeKind = .manhole
        state.centralMeridianText = "117"
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))

        state.clearAll()

        #expect(state.project.points.isEmpty)
        #expect(state.selection == nil)
        #expect(state.activeKind == .pole)
        #expect(state.centralMeridianText == "", "清空后不应残留上一次的中央子午线")
    }

    // MARK: 保存/打开

    @Test("中央子午线设置能随工程保存并读回")
    func centralMeridianPersists() throws {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))
        state.centralMeridianText = "114.5"
        #expect(state.projection.centralMeridian == 114.5)

        let url = tempURL("hzmap")
        defer { try? FileManager.default.removeItem(at: url) }
        try state.save(to: url)

        let reopened = AppState()
        try reopened.load(from: url)
        #expect(reopened.centralMeridianText == "114.5")
        #expect(reopened.project.points.count == 1)
        #expect(reopened.project.name == "测试工程")
    }

    @Test("非法中央子午线输入不会污染工程设置")
    func invalidMeridianIgnored() {
        let state = makeState()
        state.centralMeridianText = "abc"
        #expect(state.project.projection.centralMeridian == nil)
        state.centralMeridianText = ""
        #expect(state.project.projection.centralMeridian == nil)
    }

    // MARK: 导出

    @Test("三种导出都能生成非空文件，DXF 含实体")
    func exportsProduceFiles() throws {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.1301, longitude: 114.0814), kind: .pole)
        state.addPoint(at: LatLon(latitude: 32.1322, longitude: 114.0831), kind: .pole)
        state.addPoint(at: LatLon(latitude: 32.1330, longitude: 114.0849), kind: .manhole)

        let dxf = tempURL("dxf"), csv = tempURL("csv"), kml = tempURL("kml"), gpx = tempURL("gpx")
        defer {
            for url in [dxf, csv, kml, gpx] { try? FileManager.default.removeItem(at: url) }
        }

        try state.exportDXF(to: dxf)
        #expect(state.message.contains("已导出 DXF"), "DXF 导出后状态栏应提示成功，实际：\(state.message)")
        try state.exportCSV(to: csv)
        #expect(state.message.contains("已导出 CSV"))
        try state.exportKML(to: kml)
        #expect(state.message.contains("已导出 KML"))
        try state.exportGPX(to: gpx)
        #expect(state.message.contains("已导出 GPX"))

        for url in [dxf, csv, kml, gpx] {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            #expect(size > 200, "\(url.lastPathComponent) 太小：\(size)")
        }

        let dxfText = String(decoding: try Data(contentsOf: dxf), as: UTF8.self)
        #expect(dxfText.contains("LWPOLYLINE"))
        #expect(dxfText.contains("EOF"))
    }

    @Test("缓存后的链路在每次改动后同步更新")
    func chainCacheStaysInSync() {
        let state = makeState()
        #expect(state.chain.pointCount == 0)

        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))
        #expect(state.chain.pointCount == 1)

        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.09))
        #expect(state.chain.segments.count == 1)

        let firstID = state.project.points[0].id
        state.movePoint(id: firstID, to: LatLon(latitude: 32.14, longitude: 114.09))
        #expect(state.chain.segments[0].length > 1000)

        state.renamePoint(id: firstID, to: "G999")
        #expect(state.chain.orderedPoints[0].name == "G999")

        state.setKind(id: firstID, kind: .station)
        #expect(state.chain.orderedPoints[0].kind == .station)

        state.project.chainMode = .nearestNeighbor
        #expect(state.chain.orderedPoints.count == 2)

        state.selection = firstID
        state.deleteSelected()
        #expect(state.chain.pointCount == 1)
        #expect(state.chain.segments.isEmpty)
    }

    @Test("点名重复时 CSV 仍按顺序给出正确段长")
    func csvHandlesDuplicateNames() throws {
        let state = makeState()
        state.project.chainMode = .sequential
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.09))
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.15))
        // 故意把两个点改成同名
        state.renamePoint(id: state.project.points[1].id, to: "G001")

        let url = tempURL("csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try state.exportCSV(to: url)

        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let rows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // 第 3 个点距上点约 5.66 km（0.06 经度），不能被同名点覆盖成 943 m
        #expect(rows[3].contains("5661"), "实际行：\(rows[3])")
    }

    @Test("KML 导出后可被自己重新导入（含线路顶点）")
    func kmlExportImportRoundTrip() throws {
        let source = makeState()
        source.addPoint(at: LatLon(latitude: 32.1301, longitude: 114.0814), kind: .pole)
        source.addPoint(at: LatLon(latitude: 32.1322, longitude: 114.0831), kind: .pole)

        let kml = tempURL("kml")
        defer { try? FileManager.default.removeItem(at: kml) }
        try source.exportKML(to: kml)

        let target = AppState()
        try target.importKML(data: Data(contentsOf: kml), sourceName: "kml")
        #expect(target.project.points.count == 4) // 2 杆位 + 2 线路顶点
        #expect(target.message.contains("导入 4 个点"))
    }

    // MARK: 导入

    @Test("CSV 导入后重名点自动改号，不覆盖原有点")
    func importMergesWithoutClobbering() throws {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08)) // G001
        let csv = "点名,纬度,经度\nG001,32.14,114.09\n新点,32.15,114.10\n"

        try state.importCSV(data: Data(csv.utf8), sourceName: "点位表.csv")
        #expect(state.project.points.count == 3)
        let names = state.project.points.map(\.name)
        #expect(names[0] == "G001")
        #expect(Set(names).count == 3, "导入后点名不应重复：\(names)")
        #expect(names.contains("新点"))
    }

    @Test("CSV 无坐标列时报错且不改变工程")
    func importFailureKeepsState() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.08))
        let bad = "姓名,电话\n张三,13800000000\n"
        #expect(throws: (any Error).self) {
            try state.importCSV(data: Data(bad.utf8))
        }
        #expect(state.project.points.count == 1)
    }

    // MARK: 面积与纠偏

    @Test("不足 3 点无面积，3 点以上有面积")
    func areaNeedsThreePoints() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.130, longitude: 114.080))
        state.addPoint(at: LatLon(latitude: 32.130, longitude: 114.090))
        #expect(state.polygonArea == nil)
        state.addPoint(at: LatLon(latitude: 32.140, longitude: 114.090))
        #expect((state.polygonArea ?? 0) > 1000)
    }

    @Test("纠偏开启后显示坐标偏移，入库时能还原")
    func correctionRoundTrip() {
        let state = makeState()
        let p = LatLon(latitude: 32.1301, longitude: 114.0814)
        #expect(state.displayCoordinate(p) == p)

        state.project.applyGCJCorrection = true
        let displayed = state.displayCoordinate(p)
        #expect(displayed != p)
        let restored = state.storageCoordinate(displayed)
        #expect(abs(restored.latitude - p.latitude) < 1e-8)
        #expect(abs(restored.longitude - p.longitude) < 1e-8)
    }

    @Test("等间距插杆：数量与预估一致、点名不冲突")
    func insertSpacing() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.1300, longitude: 114.0800))
        state.addPoint(at: LatLon(latitude: 32.1300, longitude: 114.0906)) // 约 1000 m
        state.spacingText = "100"
        let estimated = state.estimatedInsertCount
        #expect(estimated == 9)

        let inserted = state.insertEvenlySpacedPoints(spacing: 100)
        #expect(inserted == 9)
        #expect(state.project.points.count == 11)
        let names = state.project.points.map(\.name)
        #expect(Set(names).count == names.count, "插入后点名重复：\(names)")
    }

    @Test("档距过大时不插点，并给出提示")
    func insertSpacingTooLarge() {
        let state = makeState()
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.0800))
        state.addPoint(at: LatLon(latitude: 32.13, longitude: 114.0805))
        let inserted = state.insertEvenlySpacedPoints(spacing: 1000)
        #expect(inserted == 0)
        #expect(state.message.contains("没有可插入"))
    }

    @Test("离线瓦片：缓存统计与清空")
    func tileCacheStats() throws {
        let state = makeState()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hzstate-tiles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        state.tileCacheRoot = root

        try state.tileCache.store(Data(repeating: 0, count: 2048), for: TileKey(z: 5, x: 1, y: 1))
        state.refreshCacheStats()
        #expect(state.cacheStats.count == 1)
        #expect(state.cacheStats.bytes >= 2048)

        state.clearTileCache()
        #expect(state.cacheStats.count == 0)
    }

    @Test("离线瓦片：按当前视野估算数量")
    func estimateVisibleTiles() {
        let state = makeState()
        #expect(state.estimateVisibleTiles() == 0) // 无视野
        state.visibleBounds = Bounds(centerLat: 32.13, centerLon: 114.08, latSpan: 0.02, lonSpan: 0.02)
        state.offlineMinZoom = 14
        state.offlineMaxZoom = 15
        let count = state.estimateVisibleTiles()
        #expect(count > 0)
        #expect(count == WebMercator.tileCount(state.visibleBounds!.inflated(by: 0.0005), zoom: 14)
                        + WebMercator.tileCount(state.visibleBounds!.inflated(by: 0.0005), zoom: 15))
    }

    @Test("应用自检脚本全部通过（与打包产物 --self-test 同一套逻辑）")
    func selfTestPasses() {
        let steps = AppSelfTest.run()
        let failed = steps.filter { !$0.ok }
        #expect(failed.isEmpty, "失败项：\(failed.map { "\($0.name)（\($0.detail)）" }.joined(separator: "; "))")
        #expect(steps.count >= 15)
    }
}
