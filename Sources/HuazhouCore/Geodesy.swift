import Foundation

public struct GeodesicSolution: Equatable, Sendable {
    /// 椭球面大地线长度（米）
    public let distance: Double
    /// 起点至终点的起始方位角（度，正北为 0，顺时针）
    public let initialAzimuth: Double
    /// 到达终点时的方位角（度）
    public let finalAzimuth: Double
}

public enum Geodesy {

    /// Vincenty 反解（WGS84）。收敛失败（近对跖点）时退回 haversine。
    public static func inverse(_ p1: LatLon, _ p2: LatLon) -> GeodesicSolution {
        let a = WGS84.a
        let b = WGS84.b
        let f = WGS84.f

        let L = toRad(p2.longitude - p1.longitude)
        let U1 = atan((1 - f) * tan(toRad(p1.latitude)))
        let U2 = atan((1 - f) * tan(toRad(p2.latitude)))
        let sinU1 = sin(U1), cosU1 = cos(U1)
        let sinU2 = sin(U2), cosU2 = cos(U2)

        var lambda = L
        var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0
        var sinAlpha = 0.0, cosSqAlpha = 0.0, cos2SigmaM = 0.0

        for _ in 0..<200 {
            let sinLambda = sin(lambda), cosLambda = cos(lambda)
            let t1 = cosU2 * sinLambda
            let t2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
            sinSigma = sqrt(t1 * t1 + t2 * t2)
            if sinSigma == 0 { return GeodesicSolution(distance: 0, initialAzimuth: 0, finalAzimuth: 0) }
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSqAlpha = 1 - sinAlpha * sinAlpha
            cos2SigmaM = cosSqAlpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha
            let C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
            let lambdaPrev = lambda
            lambda = L + (1 - C) * f * sinAlpha
                * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            if abs(lambda - lambdaPrev) < 1e-12 { break }
            if abs(lambda) > .pi { break }
        }

        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
            - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
        let s = b * A * (sigma - deltaSigma)

        guard s.isFinite, sinSigma.isFinite, s >= 0 else {
            let d = haversine(p1, p2)
            return GeodesicSolution(distance: d, initialAzimuth: bearing(p1, p2), finalAzimuth: bearing(p2, p1) + 180)
        }

        let alpha1 = atan2(cosU2 * sin(lambda), cosU1 * sinU2 - sinU1 * cosU2 * cos(lambda))
        let alpha2 = atan2(cosU1 * sin(lambda), -sinU1 * cosU2 + cosU1 * sinU2 * cos(lambda))
        return GeodesicSolution(
            distance: s,
            initialAzimuth: normalizeAzimuth(toDeg(alpha1)),
            finalAzimuth: normalizeAzimuth(toDeg(alpha2))
        )
    }

    public static func distance(_ p1: LatLon, _ p2: LatLon) -> Double {
        inverse(p1, p2).distance
    }

    /// 起始方位角（度，0~360）
    public static func bearing(_ p1: LatLon, _ p2: LatLon) -> Double {
        inverse(p1, p2).initialAzimuth
    }

    public static func haversine(_ p1: LatLon, _ p2: LatLon) -> Double {
        let dLat = toRad(p2.latitude - p1.latitude)
        let dLon = toRad(p2.longitude - p1.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(toRad(p1.latitude)) * cos(toRad(p2.latitude)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * WGS84.a * asin(min(1, sqrt(h)))
    }

    /// 方位角归一化到 [0, 360)
    public static func normalizeAzimuth(_ deg: Double) -> Double {
        var v = deg.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }

    /// 方位角转象限角描述（如 "北偏东 32°15'"）
    public static func quadrantDescription(_ azimuth: Double) -> String {
        let az = normalizeAzimuth(azimuth)
        let (prefix, ref): (String, Double)
        switch az {
        case 0..<90: (prefix, ref) = ("北偏东", az)
        case 90..<180: (prefix, ref) = ("南偏东", 180 - az)
        case 180..<270: (prefix, ref) = ("南偏西", az - 180)
        default: (prefix, ref) = ("北偏西", 360 - az)
        }
        let d = Int(ref)
        let m = Int((ref - Double(d)) * 60)
        return String(format: "%@ %d°%02d'", prefix, d, m)
    }
}
