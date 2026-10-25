import MapKit
import HuazhouCore

/// 优先读本地缓存的瓦片覆盖层：命中缓存直接返回，未命中走网络并回写缓存。
final class CachedTileOverlay: MKTileOverlay {
    private let cache: TileCache

    init(urlTemplate: String, cache: TileCache) {
        self.cache = cache
        super.init(urlTemplate: urlTemplate)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        let key = TileKey(z: path.z, x: path.x, y: path.y)
        if let cached = cache.data(for: key) {
            result(cached, nil)
            return
        }
        super.loadTile(at: path) { [cache] data, error in
            if let data, !data.isEmpty {
                try? cache.store(data, for: key)
            }
            result(data, error)
        }
    }
}
