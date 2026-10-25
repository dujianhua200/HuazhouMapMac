import Foundation

/// 经纬度矩形范围
public struct Bounds: Codable, Hashable, Sendable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// 以中心点 + 跨度构造
    public init(centerLat: Double, centerLon: Double, latSpan: Double, lonSpan: Double) {
        let halfLat = latSpan / 2
        let halfLon = lonSpan / 2
        self.south = max(-85.05112878, centerLat - halfLat)
        self.north = min(85.05112878, centerLat + halfLat)
        self.west = centerLon - halfLon
        self.east = centerLon + halfLon
    }

    public var center: LatLon {
        LatLon(latitude: (south + north) / 2, longitude: (west + east) / 2)
    }

    /// 小范围放大，避免边界瓦片被裁掉
    public func inflated(by degree: Double) -> Bounds {
        Bounds(south: south - degree, west: west - degree, north: north + degree, east: east + degree)
    }
}

/// Web Mercator（EPSG:3857）瓦片换算，与所有主流瓦片服务一致
public enum WebMercator {
    public static let tileSize = 256

    public static func tileX(longitude: Double, zoom: Int) -> Int {
        let n = Double(1 << zoom)
        return Int(floor((longitude + 180.0) / 360.0 * n))
    }

    public static func tileY(latitude: Double, zoom: Int) -> Int {
        let n = Double(1 << zoom)
        let clamped = min(max(latitude, -85.05112878), 85.05112878)
        let rad = clamped * Double.pi / 180
        return Int(floor((1 - log(tan(rad) + 1 / cos(rad)) / Double.pi) / 2 * n))
    }

    /// 给定范围与级别，返回瓦片行列范围（闭区间）
    public static func tileRange(_ bounds: Bounds, zoom: Int) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        let maxIndex = (1 << zoom) - 1
        let minX = max(0, tileX(longitude: bounds.west, zoom: zoom))
        let maxX = min(maxIndex, tileX(longitude: bounds.east, zoom: zoom))
        // 纬度越高 tileY 越小
        let minY = max(0, tileY(latitude: bounds.north, zoom: zoom))
        let maxY = min(maxIndex, tileY(latitude: bounds.south, zoom: zoom))
        guard minX <= maxX, minY <= maxY else { return nil }
        return (minX, maxX, minY, maxY)
    }

    /// 某级别下覆盖该范围的瓦片数量
    public static func tileCount(_ bounds: Bounds, zoom: Int) -> Int {
        guard let r = tileRange(bounds, zoom: zoom) else { return 0 }
        return (r.maxX - r.minX + 1) * (r.maxY - r.minY + 1)
    }

    /// 某级别下覆盖该范围的全部瓦片
    public static func tiles(_ bounds: Bounds, zoom: Int) -> [TileKey] {
        guard let r = tileRange(bounds, zoom: zoom) else { return [] }
        var keys: [TileKey] = []
        keys.reserveCapacity((r.maxX - r.minX + 1) * (r.maxY - r.minY + 1))
        for y in r.minY...r.maxY {
            for x in r.minX...r.maxX {
                keys.append(TileKey(z: zoom, x: x, y: y))
            }
        }
        return keys
    }

    /// 某级别下的地面分辨率（米/像素），用于估算下载量
    public static func resolution(latitude: Double, zoom: Int) -> Double {
        let earth = 2 * Double.pi * 6_378_137.0
        return earth * cos(latitude * Double.pi / 180) / Double(tileSize * (1 << zoom))
    }
}

public struct TileKey: Hashable, Codable, Sendable {
    public let z: Int
    public let x: Int
    public let y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }

    /// 磁盘路径：z/x/y.png
    public var relativePath: String { "\(z)/\(x)/\(y).png" }
}

/// 本地瓦片缓存（离线地图）。目录结构 z/x/y.png，按需读、下载后写。
public struct TileCache: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HuazhouMap/Tiles", isDirectory: true)
    }

    public func fileURL(for key: TileKey) -> URL {
        root.appendingPathComponent(key.relativePath)
    }

    public func data(for key: TileKey) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    public func contains(_ key: TileKey) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

    public func store(_ data: Data, for key: TileKey) throws {
        let url = fileURL(for: key)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// 已缓存瓦片数与占用字节
    public func stats() -> (count: Int, bytes: Int) {
        guard let en = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }
        var count = 0
        var bytes = 0
        for case let url as URL in en {
            guard url.pathExtension.lowercased() == "png" else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                count += 1
                bytes += values?.fileSize ?? 0
            }
        }
        return (count, bytes)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }
}

/// 瓦片 URL 模板：支持 {z}/{x}/{y}/{-y}/{s}
public enum TileURLTemplate {
    public static func expand(_ template: String, key: TileKey) -> URL? {
        guard !template.isEmpty else { return nil }
        let flipped = (1 << key.z) - 1 - key.y
        let subdomains = Array("0123")
        let sub = String(subdomains[(key.x + key.y) % subdomains.count])
        let filled = template
            .replacingOccurrences(of: "{-y}", with: String(flipped))
            .replacingOccurrences(of: "{z}", with: String(key.z))
            .replacingOccurrences(of: "{x}", with: String(key.x))
            .replacingOccurrences(of: "{y}", with: String(key.y))
            .replacingOccurrences(of: "{s}", with: sub)
        return URL(string: filled)
    }
}

public struct DownloadProgress: Sendable, Equatable {
    public let done: Int
    public let total: Int
    public let failed: Int

    public init(done: Int, total: Int, failed: Int) {
        self.done = done
        self.total = total
        self.failed = failed
    }

    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// 批量下载瓦片到本地缓存
public enum TileDownloader {

    public static func plan(bounds: Bounds, zooms: ClosedRange<Int>) -> [TileKey] {
        zooms.flatMap { WebMercator.tiles(bounds, zoom: $0) }
    }

    /// 已缓存的跳过；失败不中断，最后返回统计
    @discardableResult
    public static func download(
        keys: [TileKey],
        template: String,
        cache: TileCache,
        concurrency: Int = 6,
        progress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async -> (ok: Int, skipped: Int, failed: Int) {
        var pending: [TileKey] = []
        var skipped = 0
        for key in keys {
            if cache.contains(key) { skipped += 1 } else { pending.append(key) }
        }
        let total = keys.count
        guard !pending.isEmpty else {
            progress?(DownloadProgress(done: total, total: total, failed: 0))
            return (0, skipped, 0)
        }

        var done = skipped
        var ok = 0
        var failed = 0
        let batch = max(1, concurrency)

        await withTaskGroup(of: Bool.self) { group in
            var index = 0
            func addTask(_ key: TileKey) {
                group.addTask {
                    guard let url = TileURLTemplate.expand(template, key: key) else { return false }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20
                    request.setValue("HuazhouMap/2", forHTTPHeaderField: "User-Agent")
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                            return false
                        }
                        try cache.store(data, for: key)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            while index < min(batch, pending.count) {
                addTask(pending[index]); index += 1
            }
            while let success = await group.next() {
                done += 1
                if success { ok += 1 } else { failed += 1 }
                progress?(DownloadProgress(done: done, total: total, failed: failed))
                if index < pending.count {
                    addTask(pending[index]); index += 1
                }
            }
        }
        return (ok, skipped, failed)
    }
}
