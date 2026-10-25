import Foundation

/// WGS84 椭球参数
public enum WGS84 {
    public static let a = 6378137.0
    public static let f = 1.0 / 298.257223563
    public static let b = a * (1 - f)
    public static let e2 = f * (2 - f)
}

public let deg2rad = Double.pi / 180.0
public let rad2deg = 180.0 / Double.pi

@inline(__always)
public func toRad(_ deg: Double) -> Double { deg * deg2rad }

@inline(__always)
public func toDeg(_ rad: Double) -> Double { rad * rad2deg }

/// 经纬度（WGS84，度）
public struct LatLon: Codable, Hashable, Sendable, CustomStringConvertible {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var description: String {
        String(format: "%.7f, %.7f", latitude, longitude)
    }

    /// 度分秒文本，与测绘习惯一致
    public var dms: String {
        func fmt(_ v: Double, positive: String, negative: String) -> String {
            let hemi = v >= 0 ? positive : negative
            let abs = Swift.abs(v)
            let d = Int(abs)
            let mFull = (abs - Double(d)) * 60
            let m = Int(mFull)
            let s = (mFull - Double(m)) * 60
            return String(format: "%@%d°%02d'%05.2f\"", hemi, d, m, s)
        }
        return fmt(latitude, positive: "N", negative: "S") + " " + fmt(longitude, positive: "E", negative: "W")
    }
}

/// 平面坐标（米）。命名遵循测绘习惯：northing 为北向（图纸 X），easting 为东向（图纸 Y）
public struct PlanarPoint: Codable, Hashable, Sendable {
    public var northing: Double
    public var easting: Double

    public init(northing: Double, easting: Double) {
        self.northing = northing
        self.easting = easting
    }
}
