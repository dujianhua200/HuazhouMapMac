import Foundation
import HuazhouCore

/// 打包后应用的端到端自检：不起窗口、不依赖辅助功能权限，
/// 直接驱动 AppState 跑一遍「打点 → 改位 → 成链 → 存储 → 导出 → 导入 → 清空」。
/// 用法：`滑洲云图.app/Contents/MacOS/HuazhouMap --self-test`
@MainActor
public enum AppSelfTest {

    public struct Step {
        public let name: String
        public let ok: Bool
        public let detail: String
    }

    public static func run() -> [Step] {
        var steps: [Step] = []
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            steps.append(Step(name: name, ok: condition, detail: detail))
        }

        let state = AppState()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hz-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. 新建工程
        state.project.name = "自检工程"
        check("新建工程为空", state.project.points.isEmpty && state.chain.pointCount == 0)

        // 2. 打点（按类型命名）
        state.addPoint(at: LatLon(latitude: 32.1301, longitude: 114.0814), kind: .pole)
        state.addPoint(at: LatLon(latitude: 32.1322, longitude: 114.0831), kind: .pole)
        state.addPoint(at: LatLon(latitude: 32.1341, longitude: 114.0855), kind: .manhole)
        let names = state.project.points.map(\.name)
        check("按类型自动编号", names == ["G001", "G002", "R001"], names.joined(separator: "/"))

        // 3. 成链与距离
        let length1 = state.chain.totalLength
        check("自动成链与算距", state.chain.segments.count == 2 && length1 > 200,
              String(format: "%.2f m / %d 段", length1, state.chain.segments.count))

        // 4. 改位（等价于拖动标注）
        state.movePoint(id: state.project.points[1].id, to: LatLon(latitude: 32.1400, longitude: 114.0900))
        let length2 = state.chain.totalLength
        check("改位后长度刷新", abs(length2 - length1) > 50,
              String(format: "%.2f → %.2f m", length1, length2))

        // 5. 切最近邻成链
        state.project.chainMode = .nearestNeighbor
        check("切换最近邻成链", state.chain.pointCount == 3 && state.chain.segments.count == 2)

        // 6. 改点名
        state.renamePoint(id: state.project.points[0].id, to: "G901")
        check("改点名生效", state.chain.orderedPoints.contains { $0.name == "G901" })

        // 7. 中央子午线
        state.centralMeridianText = "114.5"
        check("中央子午线写入工程", state.project.projection.centralMeridian == 114.5,
              String(state.project.projection.centralMeridian ?? -1))

        // 8. 保存
        let projectURL = tmp.appendingPathComponent("selftest.hzmap")
        var saveOK = true
        do { try state.save(to: projectURL) } catch { saveOK = false }
        let savedSize = ((try? FileManager.default.attributesOfItem(atPath: projectURL.path)[.size]) as? Int) ?? 0
        check("保存工程", saveOK && savedSize > 200, "\(savedSize) 字节")

        // 9. 重新加载
        let reopened = AppState()
        var loadOK = true
        do { try reopened.load(from: projectURL) } catch { loadOK = false }
        check("重新打开工程",
              loadOK && reopened.project.points.count == 3 && reopened.centralMeridianText == "114.5",
              "\(reopened.project.points.count) 点 / 中央子午线 \(reopened.centralMeridianText)")

        // 10. 四种导出
        let exports: [(String, URL)] = [
            ("DXF", tmp.appendingPathComponent("out.dxf")),
            ("CSV", tmp.appendingPathComponent("out.csv")),
            ("KML", tmp.appendingPathComponent("out.kml")),
            ("GPX", tmp.appendingPathComponent("out.gpx")),
        ]
        for (label, url) in exports {
            var ok = true
            do {
                switch label {
                case "DXF": try state.exportDXF(to: url)
                case "CSV": try state.exportCSV(to: url)
                case "KML": try state.exportKML(to: url)
                default: try state.exportGPX(to: url)
                }
            } catch { ok = false }
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int) ?? 0
            let text = (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let marker: Bool
            switch label {
            case "DXF": marker = text.contains("LWPOLYLINE") && text.contains("EOF")
            case "CSV": marker = text.contains("纬度,经度")
            case "KML": marker = text.contains("<Placemark>")
            default: marker = text.contains("<gpx")
            }
            check("导出 \(label)", ok && size > 200 && marker, "\(size) 字节")
        }

        // 11. CSV 导入（含重名）
        let csv = "点名,纬度,经度\nG001,32.1500,114.0900\n补点,32.1600,114.0950\n"
        var importOK = true
        do { try state.importCSV(data: Data(csv.utf8), sourceName: "自检.csv") } catch { importOK = false }
        let afterImport = state.project.points.map(\.name)
        check("CSV 导入并自动改号",
              importOK && afterImport.count == 5 && Set(afterImport).count == 5,
              afterImport.joined(separator: "/"))

        // 12. 离线瓦片：规划 + 缓存读写 + 统计
        state.tileCacheRoot = tmp.appendingPathComponent("tiles")
        let view = Bounds(centerLat: 32.13, centerLon: 114.08, latSpan: 0.02, lonSpan: 0.02)
        let plan = TileDownloader.plan(bounds: view, zooms: 14...15)
        check("离线瓦片规划", !plan.isEmpty && Set(plan).count == plan.count, "\(plan.count) 块（z14-15）")

        var cacheOK = true
        let testKey = TileKey(z: 14, x: 1, y: 1)
        do {
            try state.tileCache.store(Data(repeating: 0x11, count: 512), for: testKey)
        } catch { cacheOK = false }
        let hit = state.tileCache.data(for: testKey)?.count ?? 0
        state.refreshCacheStats()
        check("瓦片缓存读写与统计", cacheOK && hit == 512 && state.cacheStats.count == 1,
              "\(state.cacheStats.count) 块 / \(state.cacheStats.sizeText)")

        state.clearTileCache()
        check("清空瓦片缓存", state.cacheStats.count == 0)

        // 13. 等间距插杆
        let beforeInsert = state.project.points.count
        state.spacingText = "200"
        let estimated = state.estimatedInsertCount
        let insertedCount = state.insertEvenlySpacedPoints(spacing: 200)
        let namesAfter = state.project.points.map(\.name)
        check("等间距插杆",
              insertedCount == estimated && state.project.points.count == beforeInsert + insertedCount
                && Set(namesAfter).count == namesAfter.count,
              "插入 \(insertedCount) 个（预估 \(estimated)），点位 \(beforeInsert)→\(state.project.points.count)")

        // 14. 清空
        state.clearAll()
        check("清空工程彻底重置",
              state.project.points.isEmpty && state.centralMeridianText.isEmpty && state.activeKind == .pole)

        return steps
    }

    /// 打印报告，返回整体是否通过
    @discardableResult
    public static func runAndReport(_ print: (String) -> Void) -> Bool {
        let steps = run()
        print("滑洲云图 自检（AppSelfTest）")
        print(String(repeating: "-", count: 46))
        for step in steps {
            let mark = step.ok ? "PASS" : "FAIL"
            let suffix = step.detail.isEmpty ? "" : "  （\(step.detail)）"
            print("[\(mark)] \(step.name)\(suffix)")
        }
        let failed = steps.filter { !$0.ok }
        print(String(repeating: "-", count: 46))
        print("\(steps.count - failed.count)/\(steps.count) 通过")
        return failed.isEmpty
    }
}
