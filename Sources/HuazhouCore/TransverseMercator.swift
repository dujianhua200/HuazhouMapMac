import Foundation

/// 高斯-克吕格投影（横轴墨卡托，k0 = 1.0），对应 PROJ 的 `+proj=tmerc`。
/// 国内 3 度带 / 6 度带均为此投影，区别只在中央子午线。
public struct TransverseMercator: Sendable {
    /// 椭球长半轴
    public let a: Double
    /// 反扁率倒数
    public let invF: Double
    /// 中央子午线（度）
    public let centralMeridian: Double
    /// 投影原点纬度（度），国内通常为 0
    public let originLatitude: Double
    /// 尺度因子，高斯投影为 1.0（UTM 为 0.9996）
    public let scaleFactor: Double
    /// 东伪偏移，国内 500000
    public let falseEasting: Double
    /// 北伪偏移
    public let falseNorthing: Double

    public init(
        centralMeridian: Double,
        originLatitude: Double = 0,
        scaleFactor: Double = 1.0,
        falseEasting: Double = 500_000,
        falseNorthing: Double = 0,
        a: Double = WGS84.a,
        invF: Double = 298.257223563
    ) {
        self.a = a
        self.invF = invF
        self.centralMeridian = centralMeridian
        self.originLatitude = originLatitude
        self.scaleFactor = scaleFactor
        self.falseEasting = falseEasting
        self.falseNorthing = falseNorthing
    }

    private var f: Double { 1.0 / invF }
    private var e2: Double { f * (2 - f) }
    private var ep2: Double { e2 / (1 - e2) }

    /// 子午线弧长（从赤道到纬度 φ，单位米）
    private func meridianArc(_ phi: Double) -> Double {
        let e4 = e2 * e2
        let e6 = e4 * e2
        return a * (
            (1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi
            - (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * phi)
            + (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * phi)
            - (35 * e6 / 3072) * sin(6 * phi)
        )
    }

    public func forward(_ p: LatLon) -> PlanarPoint {
        let phi = toRad(p.latitude)
        let lambda = toRad(p.longitude)
        let lambda0 = toRad(centralMeridian)
        let phi0 = toRad(originLatitude)

        let sinPhi = sin(phi), cosPhi = cos(phi)
        let N = a / sqrt(1 - e2 * sinPhi * sinPhi)
        let T = (sinPhi / cosPhi) * (sinPhi / cosPhi)
        let C = ep2 * cosPhi * cosPhi
        let A = (lambda - lambda0) * cosPhi

        let A2 = A * A
        let A3 = A2 * A
        let A4 = A3 * A
        let A5 = A4 * A
        let A6 = A5 * A

        let x = scaleFactor * N * (
            A + (1 - T + C) * A3 / 6
            + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * A5 / 120
        )
        let y = scaleFactor * (
            meridianArc(phi) - meridianArc(phi0)
            + N * (sinPhi / cosPhi) * (
                A2 / 2
                + (5 - T + 9 * C + 4 * C * C) * A4 / 24
                + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * A6 / 720
            )
        )
        return PlanarPoint(northing: y + falseNorthing, easting: x + falseEasting)
    }

    public func inverse(_ p: PlanarPoint) -> LatLon {
        let x = p.easting - falseEasting
        let y = p.northing - falseNorthing

        let M = y / scaleFactor + meridianArc(toRad(originLatitude))
        let mu = M / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256))
        let e1 = (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2))
        let e1_2 = e1 * e1, e1_3 = e1_2 * e1, e1_4 = e1_3 * e1

        let phi1 = mu
            + (3 * e1 / 2 - 27 * e1_3 / 32) * sin(2 * mu)
            + (21 * e1_2 / 16 - 55 * e1_4 / 32) * sin(4 * mu)
            + (151 * e1_3 / 96) * sin(6 * mu)
            + (1097 * e1_4 / 512) * sin(8 * mu)

        let sinPhi1 = sin(phi1), cosPhi1 = cos(phi1)
        let C1 = ep2 * cosPhi1 * cosPhi1
        let T1 = (sinPhi1 / cosPhi1) * (sinPhi1 / cosPhi1)
        let N1 = a / sqrt(1 - e2 * sinPhi1 * sinPhi1)
        let R1 = a * (1 - e2) / pow(1 - e2 * sinPhi1 * sinPhi1, 1.5)
        let D = x / (N1 * scaleFactor)

        let D2 = D * D, D3 = D2 * D, D4 = D3 * D, D5 = D4 * D, D6 = D5 * D

        let phi = phi1 - (N1 * sinPhi1 / cosPhi1 / R1) * (
            D2 / 2
            - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * D4 / 24
            + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * D6 / 720
        )
        let lambda = toRad(centralMeridian) + (
            D - (1 + 2 * T1 + C1) * D3 / 6
            + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * D5 / 120
        ) / cosPhi1

        return LatLon(latitude: toDeg(phi), longitude: toDeg(lambda))
    }
}

/// 高斯-克吕格分带
public enum GaussKrugerZone {

    /// 3 度带带号（带号 n，中央子午线 = 3n）
    public static func zoneNumber3(_ longitude: Double) -> Int {
        Int((longitude / 3.0).rounded())
    }

    public static func centralMeridian3(_ longitude: Double) -> Double {
        Double(zoneNumber3(longitude)) * 3.0
    }

    /// 6 度带带号（带号 n，中央子午线 = 6n - 3）
    public static func zoneNumber6(_ longitude: Double) -> Int {
        Int(floor(longitude / 6.0)) + 1
    }

    public static func centralMeridian6(_ longitude: Double) -> Double {
        Double(zoneNumber6(longitude)) * 6.0 - 3.0
    }
}
