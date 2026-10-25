import Testing
import Foundation
@testable import HuazhouCore

@Suite("离线瓦片：坐标换算与缓存")
struct TileCacheTests {

    @Test("赤道与本初子午线落在 z 级对角瓦片中心")
    func originTile() {
        #expect(WebMercator.tileX(longitude: 0, zoom: 14) == 8192)
        #expect(WebMercator.tileY(latitude: 0, zoom: 14) == 8192)
        #expect(WebMercator.tileX(longitude: -180, zoom: 0) == 0)
    }

    @Test("信阳的瓦片范围包含中心点所在瓦片，且行列数为正")
    func tileRangeContainsCenter() {
        let bounds = Bounds(centerLat: 32.1301, centerLon: 114.0814, latSpan: 0.02, lonSpan: 0.02)
        guard let range = WebMercator.tileRange(bounds, zoom: 14) else {
            Issue.record("未算出瓦片范围"); return
        }
        let cx = WebMercator.tileX(longitude: 114.0814, zoom: 14)
        let cy = WebMercator.tileY(latitude: 32.1301, zoom: 14)
        #expect(range.minX <= cx && cx <= range.maxX)
        #expect(range.minY <= cy && cy <= range.maxY)
        #expect(range.maxX - range.minX + 1 >= 1)
    }

    @Test("瓦片数量等于行列乘积")
    func tileCountMatchesGrid() {
        let bounds = Bounds(centerLat: 32.13, centerLon: 114.08, latSpan: 0.05, lonSpan: 0.05)
        let zoom = 16
        let range = WebMercator.tileRange(bounds, zoom: zoom)!
        let cols = range.maxX - range.minX + 1
        let rows = range.maxY - range.minY + 1
        #expect(WebMercator.tileCount(bounds, zoom: zoom) == cols * rows)
        #expect(WebMercator.tiles(bounds, zoom: zoom).count == cols * rows)
    }

    @Test("URL 模板支持 {z}/{x}/{y}/{-y}/{s}")
    func templateExpansion() {
        let key = TileKey(z: 12, x: 3, y: 5)
        let url = TileURLTemplate.expand("https://tile.example.com/{z}/{x}/{y}.png", key: key)
        #expect(url?.absoluteString == "https://tile.example.com/12/3/5.png")

        let tms = TileURLTemplate.expand("https://x/{z}/{x}/{-y}.png", key: key)
        #expect(tms?.absoluteString == "https://x/12/3/4090.png")  // 2^12-1-5 = 4090

        let sub = TileURLTemplate.expand("https://webrd0{s}.example.com/{x}/{y}/{z}", key: key)
        #expect(sub?.absoluteString.contains("webrd0") == true)
        #expect(sub?.absoluteString.contains("{s}") == false)
    }

    @Test("缓存可写、可读、可统计、可清空")
    func cacheRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tilecache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = TileCache(root: root)
        let key = TileKey(z: 3, x: 1, y: 2)
        let payload = Data(repeating: 0xAB, count: 1024)

        #expect(!cache.contains(key))
        try cache.store(payload, for: key)
        #expect(cache.contains(key))
        #expect(cache.data(for: key) == payload)

        let stats = cache.stats()
        #expect(stats.count == 1)
        #expect(stats.bytes >= 1024)

        try cache.clear()
        #expect(cache.stats().count == 0)
    }

    @Test("下载计划按级别展开，级别越多瓦片越多")
    func downloadPlan() {
        let bounds = Bounds(centerLat: 32.13, centerLon: 114.08, latSpan: 0.02, lonSpan: 0.02)
        let p1 = TileDownloader.plan(bounds: bounds, zooms: 14...14)
        let p3 = TileDownloader.plan(bounds: bounds, zooms: 12...14)
        #expect(!p1.isEmpty)
        #expect(p3.count > p1.count)
        #expect(Set(p3).count == p3.count)
    }

    @Test("分辨率随级别翻倍而减半")
    func resolutionHalves() {
        let z14 = WebMercator.resolution(latitude: 32.13, zoom: 14)
        let z15 = WebMercator.resolution(latitude: 32.13, zoom: 15)
        #expect(abs(z14 / z15 - 2) < 0.0001)
        #expect(z14 > 5 && z14 < 10)  // 北纬 32° z14 约 8 m/像素
    }
}

@Suite("等间距插杆")
struct RoutePlannerTests {

    @Test("1000 m 段按 100 m 档距插 9 个点，首点约在 100 m 处")
    func interpolateSpacing() {
        let from = LatLon(latitude: 32.13, longitude: 114.08)
        let to = LatLon(latitude: 32.13, longitude: 114.0906) // 约 1000 m
        let points = RoutePlanner.interpolate(from: from, to: to, spacing: 100)
        #expect(points.count == 9)
        let firstLeg = Geodesy.distance(from, points[0])
        #expect(abs(firstLeg - 100) < 2)
        // 相邻间隔一致
        let secondLeg = Geodesy.distance(points[0], points[1])
        #expect(abs(secondLeg - 100) < 2)
    }

    @Test("档距大于段长时不插点")
    func noInsertWhenTooShort() {
        let from = LatLon(latitude: 32.13, longitude: 114.08)
        let to = LatLon(latitude: 32.13, longitude: 114.0805) // 约 47 m
        #expect(RoutePlanner.interpolate(from: from, to: to, spacing: 100).isEmpty)
    }

    @Test("非法档距不产生点")
    func invalidSpacing() {
        let from = LatLon(latitude: 32.13, longitude: 114.08)
        let to = LatLon(latitude: 32.14, longitude: 114.09)
        #expect(RoutePlanner.interpolate(from: from, to: to, spacing: 0).isEmpty)
        #expect(RoutePlanner.interpolate(from: from, to: to, spacing: -50).isEmpty)
    }

    @Test("整链加密：插入点数量与预估一致，且总长基本不变")
    func densifyChain() {
        let points = [
            SurveyPoint(name: "G001", coordinate: LatLon(latitude: 32.1300, longitude: 114.0800)),
            SurveyPoint(name: "G002", coordinate: LatLon(latitude: 32.1300, longitude: 114.0906)),
            SurveyPoint(name: "G003", coordinate: LatLon(latitude: 32.1300, longitude: 114.1012)),
        ]
        let chain = ChainBuilder.build(points, mode: .sequential)
        let estimated = RoutePlanner.estimatedInsertCount(chain: chain, spacing: 100)
        let inserted = RoutePlanner.densify(chain: chain, spacing: 100)
        #expect(inserted.count == estimated)
        #expect(inserted.count == 18)

        // 插点不改变链路总长（同一折线）
        var merged = points
        merged.append(contentsOf: inserted)
        merged.sort { $0.coordinate.longitude < $1.coordinate.longitude }
        let densified = ChainBuilder.build(merged, mode: .sequential)
        #expect(abs(densified.totalLength - chain.totalLength) < 1.0)
    }
}
