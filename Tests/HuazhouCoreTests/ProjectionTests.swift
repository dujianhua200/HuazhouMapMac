import Testing
@testable import HuazhouCore

@Suite("高斯-克吕格投影")
struct ProjectionTests {

    @Test("分带号与中央子午线")
    func zoneNumbers() {
        #expect(GaussKrugerZone.zoneNumber3(114.0814) == 38)
        #expect(GaussKrugerZone.centralMeridian3(114.0814) == 114)
        #expect(GaussKrugerZone.zoneNumber6(114.0814) == 20)
        #expect(GaussKrugerZone.centralMeridian6(114.0814) == 117)
        #expect(GaussKrugerZone.centralMeridian3(115.6) == 117)
    }

    @Test("中央子午线上东坐标为 500000，北坐标为子午线弧长")
    func centralMeridianHasFalseEasting() {
        let tm = TransverseMercator(centralMeridian: 114)
        let p = tm.forward(LatLon(latitude: 32.13, longitude: 114))
        #expect(abs(p.easting - 500_000) < 1e-6)
        #expect(abs(p.northing - 3_556_267.87) < 0.5)
    }

    @Test("正算后反算可无损回到原经纬度")
    func forwardInverseRoundTrip() {
        let tm = TransverseMercator(centralMeridian: 114)
        for lat in stride(from: 31.9, through: 32.4, by: 0.1) {
            for lon in stride(from: 113.7, through: 114.3, by: 0.1) {
                let original = LatLon(latitude: lat, longitude: lon)
                let back = tm.inverse(tm.forward(original))
                #expect(abs(back.latitude - original.latitude) < 1e-9)
                #expect(abs(back.longitude - original.longitude) < 1e-9)
            }
        }
    }

    @Test("局部比例尺符合北纬 32° 的实际米数")
    func localScaleIsPhysicallyPlausible() {
        let tm = TransverseMercator(centralMeridian: 114)
        let base = LatLon(latitude: 32.13, longitude: 114.0814)
        let p0 = tm.forward(base)

        let northward = tm.forward(LatLon(latitude: base.latitude + 0.001, longitude: base.longitude))
        let eastward = tm.forward(LatLon(latitude: base.latitude, longitude: base.longitude + 0.001))

        // 0.001° 纬度约 110.89 m，0.001° 经度约 94.36 m
        #expect(abs((northward.northing - p0.northing) - 110.89) < 1.0)
        #expect(abs((eastward.easting - p0.easting) - 94.36) < 1.0)
    }

    @Test("按参考点自动选带")
    func projectorSelectsZoneFromReference() {
        let projector = Projector(
            setting: ProjectionSetting(kind: .gaussKruger3),
            reference: LatLon(latitude: 32.13, longitude: 114.08)
        )
        #expect(projector.effectiveMeridian == 114)
        #expect(projector.zone == 38)
    }

    @Test("可指定自定义中央子午线")
    func projectorHonoursCustomMeridian() {
        let projector = Projector(
            setting: ProjectionSetting(kind: .gaussKruger3, centralMeridian: 114.5),
            reference: LatLon(latitude: 32.13, longitude: 114.08)
        )
        #expect(projector.effectiveMeridian == 114.5)
    }

    @Test("本地平面以原点为 (0,0)")
    func localPlaneOriginIsZero() {
        let origin = LatLon(latitude: 32.1301, longitude: 114.0814)
        let projector = Projector(setting: ProjectionSetting(kind: .localPlane), reference: origin)
        let plan = projector.project(origin).plan
        #expect(abs(plan.northing) < 1e-9)
        #expect(abs(plan.easting) < 1e-9)

        let moved = projector.project(LatLon(latitude: origin.latitude, longitude: origin.longitude + 0.01)).plan
        #expect(abs(moved.easting - 943.6) < 2.0)
        #expect(abs(moved.northing) < 1e-9)
    }
}
