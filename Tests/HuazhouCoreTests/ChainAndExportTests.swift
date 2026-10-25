import Testing
import Foundation
@testable import HuazhouCore

@Suite("连杆与距离统计")
struct ChainTests {

    /// 沿正东方向按给定段长排出一串点（1° 经度约 94359 m @ 32.13°N）
    private func line(lengths: [Double], start: LatLon = LatLon(latitude: 32.13, longitude: 114.08)) -> [SurveyPoint] {
        var points: [SurveyPoint] = [SurveyPoint(name: "G001", coordinate: start)]
        var cumulative = 0.0
        for (i, length) in lengths.enumerated() {
            cumulative += length
            let lon = start.longitude + cumulative / 94_359.44
            points.append(
                SurveyPoint(name: String(format: "G%03d", i + 2), coordinate: LatLon(latitude: 32.13, longitude: lon))
            )
        }
        return points
    }

    @Test("顺序成链时累计长度与方位角正确")
    func sequentialChainAccumulates() {
        let chain = ChainBuilder.build(line(lengths: [100, 100, 100]), mode: .sequential)
        #expect(chain.segments.count == 3)
        #expect(abs(chain.totalLength - 300) < 1.0)
        #expect(abs(chain.segments[2].cumulative - 300) < 1.0)
        #expect(abs(chain.segments[0].azimuth - 90) < 0.1)
        #expect(abs(chain.averageSegment - 100) < 1.0)
    }

    @Test("单点不产生线段")
    func singlePointProducesNoSegments() {
        let chain = ChainBuilder.build(
            [SurveyPoint(name: "G001", coordinate: LatLon(latitude: 32.13, longitude: 114.08))],
            mode: .sequential
        )
        #expect(chain.isEmpty)
        #expect(chain.totalLength == 0)
    }

    @Test("乱序打点后最近邻成链更短，且从首点出发")
    func nearestNeighborReordersAndShortens() {
        var points = line(lengths: [100, 100, 100])
        points.swapAt(1, 2) // 打点顺序变成 0, 200, 100, 300 米
        let sequential = ChainBuilder.build(points, mode: .sequential)
        let nearest = ChainBuilder.build(points, mode: .nearestNeighbor)

        #expect(nearest.totalLength < sequential.totalLength)
        #expect(nearest.orderedPoints.first?.name == "G001")
        #expect(nearest.orderedPoints.map(\.name) == ["G001", "G002", "G003", "G004"])
    }

    @Test("已经有序的数据不因最近邻而改变")
    func nearestNeighborKeepsOrderedChain() {
        let points = line(lengths: [50, 50, 50])
        let nearest = ChainBuilder.build(points, mode: .nearestNeighbor)
        #expect(nearest.orderedPoints.map(\.name) == points.map(\.name))
    }
}

@Suite("导出与工程文件")
struct ExportTests {

    private var points: [SurveyPoint] {
        [
            SurveyPoint(name: "G001", coordinate: LatLon(latitude: 32.1301, longitude: 114.0814), note: "12m 水泥杆"),
            SurveyPoint(name: "G002", coordinate: LatLon(latitude: 32.1306, longitude: 114.0820)),
            SurveyPoint(name: "G003", coordinate: LatLon(latitude: 32.1312, longitude: 114.0827)),
        ]
    }

    @Test("DXF 结构完整，每根杆一个圆符号")
    func dxfStructure() {
        let chain = ChainBuilder.build(points, mode: .sequential)
        let dxf = DXFWriter.makeDXF(
            points: points,
            chain: chain,
            options: DXFExportOptions(projection: ProjectionSetting(kind: .gaussKruger3))
        )

        #expect(dxf.hasPrefix("0\r\nSECTION"))
        #expect(dxf.hasSuffix("0\r\nEOF\r\n"))
        #expect(dxf.contains("$ACADVER"))
        #expect(dxf.contains("AC1015"))
        #expect(dxf.contains("LWPOLYLINE"))
        #expect(dxf.components(separatedBy: "\r\nCIRCLE\r\n").count - 1 == points.count)
        #expect(dxf.contains(DXFWriter.Layer.pole))
        #expect(dxf.contains(DXFWriter.Layer.lengthLabel))
    }

    @Test("DXF 的 X 用东坐标、Y 用北坐标")
    func dxfUsesEastingAsXAndNorthingAsY() {
        let chain = ChainBuilder.build(points, mode: .sequential)
        let options = DXFExportOptions(projection: ProjectionSetting(kind: .gaussKruger3))
        let dxf = DXFWriter.makeDXF(points: points, chain: chain, options: options)

        let plan = Projector(setting: options.projection, reference: points[0].coordinate)
            .project(points[0].coordinate).plan
        let expectedX = String(format: "%.4f", plan.easting)
        let expectedY = String(format: "%.4f", plan.northing)
        #expect(dxf.contains("10\r\n\(expectedX)"), "缺少东坐标 \(expectedX)")
        #expect(dxf.contains("20\r\n\(expectedY)"), "缺少北坐标 \(expectedY)")
    }

    @Test("GB18030 编码保证中文在国产 CAD 正常显示")
    func gb18030EncodingPreservesChinese() {
        let data = DXFWriter.gb18030Data("电杆")
        #expect(data.count == 4) // GB18030 每汉字 2 字节
        #expect(data != Data("电杆".utf8))
    }

    @Test("CSV 含全部点位与合计")
    func csvContainsAllPointsAndTotal() {
        let chain = ChainBuilder.build(points, mode: .sequential)
        let csv = CSVWriter.makeCSV(points: points, chain: chain, projection: ProjectionSetting(kind: .gaussKruger3))
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(rows.count == 5) // 表头 + 3 点 + 合计
        #expect(rows[0].hasPrefix("序号,点名"))
        #expect(rows[1].contains("G001"))
        #expect(rows.last!.hasPrefix("合计"))
        #expect(csv.contains("12m 水泥杆"))
    }

    @Test("工程文件 JSON 往返无损")
    func projectJSONRoundTrip() throws {
        var project = SurveyProject(name: "信阳—平桥光缆")
        project.points = points
        project.chainMode = .nearestNeighbor
        project.projection = ProjectionSetting(kind: .gaussKruger6, centralMeridian: 117)

        let restored = try SurveyProject.load(from: try project.jsonData())
        #expect(restored.name == project.name)
        #expect(restored.points.count == 3)
        #expect(restored.points[0].name == "G001")
        #expect(restored.chainMode == .nearestNeighbor)
        #expect(restored.projection.kind == .gaussKruger6)
        #expect(restored.projection.centralMeridian == 117)
    }

    @Test("自动点名会跳过已用编号")
    func nextPointNameSkipsExisting() {
        var project = SurveyProject()
        project.points = points
        #expect(project.nextPointName() == "G004")
        project.points.append(SurveyPoint(name: "G004", coordinate: LatLon(latitude: 0, longitude: 0)))
        #expect(project.nextPointName() == "G005")
    }
}
