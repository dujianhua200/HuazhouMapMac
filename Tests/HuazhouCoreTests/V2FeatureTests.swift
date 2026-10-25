import Testing
import Foundation
@testable import HuazhouCore

@Suite("坐标纠偏 GCJ-02")
struct CoordinateCorrectionTests {

    @Test("信阳的点位偏移量与公开算法量级一致（50~800 m）")
    func offsetMagnitude() {
        let p = LatLon(latitude: 32.1301, longitude: 114.0814)
        let offset = CoordinateCorrection.offsetMeters(p)
        #expect(offset > 50 && offset < 800)
    }

    @Test("WGS84→GCJ-02→WGS84 往返精度优于 1e-9 度")
    func roundTrip() {
        let p = LatLon(latitude: 32.1301, longitude: 114.0814)
        let back = CoordinateCorrection.gcj02ToWGS84(CoordinateCorrection.wgs84ToGCJ02(p))
        #expect(abs(back.latitude - p.latitude) < 1e-9)
        #expect(abs(back.longitude - p.longitude) < 1e-9)
    }

    @Test("境外不偏移")
    func outsideChinaUnchanged() {
        let p = LatLon(latitude: 48.8566, longitude: 2.3522)
        let q = CoordinateCorrection.wgs84ToGCJ02(p)
        #expect(q.latitude == p.latitude)
        #expect(q.longitude == p.longitude)
    }
}

@Suite("几何量算")
struct GeometryTests {

    @Test("约 100 m × 100 m 的正方形面积≈10000 m²")
    func squareArea() {
        // 32.13°N：0.0009° 纬度≈99.8 m，0.00106° 经度≈100 m
        let dLat = 0.0009
        let dLon = 0.00106
        let origin = LatLon(latitude: 32.13, longitude: 114.08)
        let ring = [
            origin,
            LatLon(latitude: origin.latitude, longitude: origin.longitude + dLon),
            LatLon(latitude: origin.latitude + dLat, longitude: origin.longitude + dLon),
            LatLon(latitude: origin.latitude + dLat, longitude: origin.longitude),
        ]
        let area = Geometry.polygonArea(ring)
        #expect(abs(area - 10_000) < 600)
        #expect(abs(Geometry.ringPerimeter(ring) - 400) < 6)
    }

    @Test("点在多边形内判定")
    func pointInPolygon() {
        let ring = [
            LatLon(latitude: 32.130, longitude: 114.080),
            LatLon(latitude: 32.130, longitude: 114.090),
            LatLon(latitude: 32.140, longitude: 114.090),
            LatLon(latitude: 32.140, longitude: 114.080),
        ]
        #expect(Geometry.contains(LatLon(latitude: 32.135, longitude: 114.085), in: ring))
        #expect(!Geometry.contains(LatLon(latitude: 32.150, longitude: 114.085), in: ring))
    }
}

@Suite("KML / GPX 导出")
struct KMLGPXTests {

    private var points: [SurveyPoint] {
        [
            SurveyPoint(name: "G001", coordinate: LatLon(latitude: 32.1301, longitude: 114.0814), note: "12m 杆", kind: .pole),
            SurveyPoint(name: "R001", coordinate: LatLon(latitude: 32.1320, longitude: 114.0830), kind: .manhole),
        ]
    }

    @Test("KML 坐标顺序为 经度,纬度")
    func kmlCoordinateOrder() {
        let chain = ChainBuilder.build(points, mode: .sequential)
        let kml = KMLWriter.makeKML(points: points, chain: chain, documentName: "测试")
        #expect(kml.contains("<kml xmlns=\"http://www.opengis.net/kml/2.2\">"))
        #expect(kml.contains("114.0814000,32.1301000,0"))
        #expect(kml.components(separatedBy: "<Placemark>").count - 1 == 3) // 2 点 + 1 线
        #expect(kml.contains("人孔"))
    }

    @Test("GPX 含航点与轨迹段")
    func gpxStructure() {
        let chain = ChainBuilder.build(points, mode: .sequential)
        let gpx = GPXWriter.makeGPX(points: points, chain: chain, name: "测试")
        #expect(gpx.contains("<gpx version=\"1.1\""))
        #expect(gpx.components(separatedBy: "<wpt").count - 1 == 2)
        #expect(gpx.contains("<trkseg>"))
        #expect(gpx.contains("lat=\"32.1301000\" lon=\"114.0814000\""))
    }

    @Test("KML 导入能读回自己导出的点")
    func kmlRoundTrip() throws {
        let chain = ChainBuilder.build(points, mode: .sequential)
        let data = Data(KMLWriter.makeKML(points: points, chain: chain, documentName: "往返").utf8)
        let imported = try KMLImporter.parse(data: data)
        // 2 个点 + 线路的 2 个顶点
        #expect(imported.count == 4)
        #expect(imported.contains { $0.name == "G001" })
        #expect(imported[0].coordinate.latitude > 32.12 && imported[0].coordinate.latitude < 32.14)
    }
}

@Suite("CSV 导入")
struct CSVImporterTests {

    @Test("读取本程序导出的点表（含投影坐标列不误判）")
    func parseOwnExport() throws {
        let csv = """
        序号,点名,纬度,经度,北坐标N,东坐标E,距上点(m),累计(m),方位角(°),象限角,备注
        1,G001,32.1301000,114.0814000,3556281.858,507680.862,,,,,12m 水泥杆
        2,G002,32.1322000,114.0831000,3556514.848,507841.094,282.77,282.77,34.56,北偏东 34°33',"9m 木杆, 旧"
        """
        let points = try CSVImporter.parse(data: Data(csv.utf8))
        #expect(points.count == 2)
        #expect(points[0].name == "G001")
        #expect(abs(points[1].coordinate.latitude - 32.1322) < 1e-9)
        #expect(points[1].note == "9m 木杆, 旧")
    }

    @Test("无表头时按数值范围自动识别经纬度列")
    func parseHeaderless() throws {
        let csv = """
        G001,32.1301,114.0814
        G002,32.1322,114.0831
        """
        let points = try CSVImporter.parse(data: Data(csv.utf8))
        #expect(points.count == 2)
        #expect(points[0].name == "G001")
        #expect(abs(points[0].coordinate.latitude - 32.1301) < 1e-9)
        #expect(abs(points[0].coordinate.longitude - 114.0814) < 1e-9)
    }

    @Test("经度在前也能识别")
    func parseLongitudeFirst() throws {
        let csv = "点名,经度,纬度\nA,114.0814,32.1301\n"
        let points = try CSVImporter.parse(data: Data(csv.utf8))
        #expect(points.count == 1)
        #expect(abs(points[0].coordinate.latitude - 32.1301) < 1e-9)
        #expect(abs(points[0].coordinate.longitude - 114.0814) < 1e-9)
    }

    @Test("无表头时保留点名与备注列（经度在前）")
    func parseHeaderlessKeepsNameAndNote() throws {
        let csv = """
        G001,114.0814,32.1301,"12m 水泥杆, 2019 年立"
        R001,114.0849,32.1330,人孔 60x60
        """
        let points = try CSVImporter.parse(data: Data(csv.utf8))
        #expect(points.count == 2)
        #expect(points[0].name == "G001")
        #expect(points[0].note == "12m 水泥杆, 2019 年立")
        #expect(points[1].name == "R001")
        #expect(points[1].note == "人孔 60x60")
    }

    @Test("空文件报错而不是静默返回")
    func emptyThrows() {
        #expect(throws: ImportError.self) {
            _ = try CSVImporter.parse(data: Data("".utf8))
        }
    }
}
