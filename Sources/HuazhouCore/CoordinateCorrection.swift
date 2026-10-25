import Foundation

/// 国测局坐标（GCJ-02，"火星坐标"）与 WGS84 互转。
/// 国内底图（高德/腾讯/百度部分图层）使用偏移坐标，用于把点位对齐到这些底图上。
public enum CoordinateCorrection {

    private static let a = 6_378_245.0
    private static let ee = 0.006_693_421_622_965_943

    /// 粗略判断是否在中国境外；境外不做偏移
    public static func isOutOfChina(_ p: LatLon) -> Bool {
        let lon = p.longitude, lat = p.latitude
        return !(lon > 73.66 && lon < 135.05 && lat > 3.86 && lat < 53.55)
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }

    /// WGS84 → GCJ-02
    public static func wgs84ToGCJ02(_ p: LatLon) -> LatLon {
        if isOutOfChina(p) { return p }
        var dLat = transformLat(p.longitude - 105.0, p.latitude - 35.0)
        var dLon = transformLon(p.longitude - 105.0, p.latitude - 35.0)
        let radLat = p.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return LatLon(latitude: p.latitude + dLat, longitude: p.longitude + dLon)
    }

    /// GCJ-02 → WGS84（迭代反解，精度优于 1e-7 度）
    public static func gcj02ToWGS84(_ p: LatLon) -> LatLon {
        if isOutOfChina(p) { return p }
        var guess = p
        for _ in 0..<5 {
            let corrected = wgs84ToGCJ02(guess)
            let dLat = corrected.latitude - p.latitude
            let dLon = corrected.longitude - p.longitude
            guess = LatLon(latitude: guess.latitude - dLat, longitude: guess.longitude - dLon)
            if abs(dLat) < 1e-10 && abs(dLon) < 1e-10 { break }
        }
        return guess
    }

    /// 偏移量（米），用于界面提示
    public static func offsetMeters(_ p: LatLon) -> Double {
        Geodesy.distance(p, wgs84ToGCJ02(p))
    }
}
