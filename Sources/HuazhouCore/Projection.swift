import Foundation

/// 出图坐标系
public enum ProjectionKind: String, Codable, CaseIterable, Sendable {
    /// 高斯-克吕格 3 度带（CGCS2000/WGS84 椭球）
    case gaussKruger3
    /// 高斯-克吕格 6 度带
    case gaussKruger6
    /// 本地平面：以首个点（或指定原点）为 (0,0) 的米制平面，适合相对定位成图
    case localPlane
    /// 直接使用经纬度（单位为度），仅用于快速检查
    case geographic

    public var displayName: String {
        switch self {
        case .gaussKruger3: return "高斯-克吕格 3 度带"
        case .gaussKruger6: return "高斯-克吕格 6 度带"
        case .localPlane: return "本地平面（以首点为原点）"
        case .geographic: return "经纬度（度）"
        }
    }
}

public struct ProjectionSetting: Codable, Hashable, Sendable {
    public var kind: ProjectionKind
    /// 自定义中央子午线；nil 表示按首个点经度自动分带
    public var centralMeridian: Double?
    /// 本地平面的原点经度；nil 时使用首个点
    public var origin: LatLon?

    public init(kind: ProjectionKind = .gaussKruger3, centralMeridian: Double? = nil, origin: LatLon? = nil) {
        self.kind = kind
        self.centralMeridian = centralMeridian
        self.origin = origin
    }
}

public struct ProjectedPoint: Sendable {
    public let plan: PlanarPoint
    /// 附加信息，如带号
    public let zone: Int?
}

/// 把经纬度批量转换到出图平面坐标
public struct Projector {
    public let setting: ProjectionSetting
    /// 实际使用的中央子午线 / 本地平面原点
    public let effectiveMeridian: Double?
    public let zone: Int?
    private let tm: TransverseMercator?
    private let localOrigin: LatLon?
    private let metersPerDegLat: Double
    private let metersPerDegLon: Double

    public init(setting: ProjectionSetting, reference: LatLon) {
        self.setting = setting
        let lon = reference.longitude
        switch setting.kind {
        case .gaussKruger3:
            let meridian = setting.centralMeridian ?? GaussKrugerZone.centralMeridian3(lon)
            self.effectiveMeridian = meridian
            self.zone = GaussKrugerZone.zoneNumber3(lon)
            self.tm = TransverseMercator(centralMeridian: meridian)
            self.localOrigin = nil
        case .gaussKruger6:
            let meridian = setting.centralMeridian ?? GaussKrugerZone.centralMeridian6(lon)
            self.effectiveMeridian = meridian
            self.zone = GaussKrugerZone.zoneNumber6(lon)
            self.tm = TransverseMercator(centralMeridian: meridian)
            self.localOrigin = nil
        case .localPlane:
            let o = setting.origin ?? reference
            self.effectiveMeridian = o.longitude
            self.zone = nil
            self.tm = nil
            self.localOrigin = o
        case .geographic:
            self.effectiveMeridian = nil
            self.zone = nil
            self.tm = nil
            self.localOrigin = nil
        }
        let phi0 = localOrigin?.latitude ?? reference.latitude
        self.metersPerDegLat = 111_132.92 - 559.82 * cos(2 * toRad(phi0))
            + 1.175 * cos(4 * toRad(phi0)) - 0.0023 * cos(6 * toRad(phi0))
        self.metersPerDegLon = 111_412.84 * cos(toRad(phi0)) - 93.5 * cos(3 * toRad(phi0))
            + 0.118 * cos(5 * toRad(phi0))
    }

    public func project(_ p: LatLon) -> ProjectedPoint {
        switch setting.kind {
        case .gaussKruger3, .gaussKruger6:
            return ProjectedPoint(plan: tm!.forward(p), zone: zone)
        case .localPlane:
            let o = localOrigin!
            return ProjectedPoint(
                plan: PlanarPoint(
                    northing: (p.latitude - o.latitude) * metersPerDegLat,
                    easting: (p.longitude - o.longitude) * metersPerDegLon
                ),
                zone: nil
            )
        case .geographic:
            return ProjectedPoint(plan: PlanarPoint(northing: p.latitude, easting: p.longitude), zone: nil)
        }
    }

    /// 单位说明，写入导出文件注释
    public var unitNote: String {
        switch setting.kind {
        case .geographic: return "单位：度"
        default: return "单位：米"
        }
    }
}
