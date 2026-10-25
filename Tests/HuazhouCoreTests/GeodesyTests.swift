import Testing
@testable import HuazhouCore

@Suite("大地线计算")
struct GeodesyTests {

    @Test("赤道 1 度经差等于椭球弧长 111319.4908 m")
    func equatorOneDegree() {
        let sol = Geodesy.inverse(
            LatLon(latitude: 0, longitude: 0),
            LatLon(latitude: 0, longitude: 1)
        )
        #expect(abs(sol.distance - 111_319.4908) < 0.001)
    }

    @Test("短距离与 haversine 交叉校验（杆路段量级）")
    func shortDistanceAgreesWithHaversine() {
        let a = LatLon(latitude: 32.1301, longitude: 114.0814)
        let b = LatLon(latitude: 32.1401, longitude: 114.0914)
        let vincenty = Geodesy.distance(a, b)
        let haversine = Geodesy.haversine(a, b)
        #expect(abs(vincenty - haversine) < haversine * 0.005)
        #expect(abs(vincenty - 1456.0) < 5.0)
    }

    @Test("同纬度向东的大地线起始方位角略小于 90°（向极地凸出）")
    func azimuthDueEast() {
        let sol = Geodesy.inverse(
            LatLon(latitude: 32, longitude: 114),
            LatLon(latitude: 32, longitude: 115)
        )
        // 球面解析解 atan(sinΔλ·cosφ2 / (cosφ1sinφ2 − sinφ1cosφ2cosΔλ)) ≈ 89.735°
        #expect(abs(sol.initialAzimuth - 89.735) < 0.01)
        #expect(sol.initialAzimuth < 90)
    }

    @Test("正北方位角为 0°")
    func azimuthDueNorth() {
        let sol = Geodesy.inverse(
            LatLon(latitude: 32, longitude: 114),
            LatLon(latitude: 33, longitude: 114)
        )
        #expect(abs(sol.initialAzimuth) < 0.01)
    }

    @Test("往返距离一致，反方位角相差 180°")
    func azimuthIsReversible() {
        let a = LatLon(latitude: 32.1301, longitude: 114.0814)
        let b = LatLon(latitude: 32.1401, longitude: 114.0914)
        let forward = Geodesy.inverse(a, b)
        let backward = Geodesy.inverse(b, a)
        #expect(abs(forward.distance - backward.distance) < 0.001)
        let reversed = Geodesy.normalizeAzimuth(backward.initialAzimuth)
        let expected = Geodesy.normalizeAzimuth(forward.initialAzimuth + 180)
        #expect(abs(reversed - expected) < 0.1)
    }

    @Test("象限角描述")
    func quadrantDescription() {
        #expect(Geodesy.quadrantDescription(45) == "北偏东 45°00'")
        #expect(Geodesy.quadrantDescription(135) == "南偏东 45°00'")
        #expect(Geodesy.quadrantDescription(225) == "南偏西 45°00'")
        #expect(Geodesy.quadrantDescription(315) == "北偏西 45°00'")
    }
}
