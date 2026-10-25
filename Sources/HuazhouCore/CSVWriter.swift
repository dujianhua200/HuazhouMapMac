import Foundation

/// 点表 CSV（UTF-8 带 BOM，Excel 直接双击可读）
public enum CSVWriter {

    public static func makeCSV(points: [SurveyPoint], chain: ChainResult, projection: ProjectionSetting) -> String {
        let reference = points.first?.coordinate ?? LatLon(latitude: 0, longitude: 0)
        let projector = Projector(setting: projection, reference: reference)

        var rows: [String] = []
        rows.append("序号,点名,纬度,经度,北坐标N,东坐标E,距上点(m),累计(m),方位角(°),象限角,备注")

        // 按链路序号取段长，避免点名重复时互相覆盖
        var segmentByOrderedIndex: [Int: ChainSegment] = [:]
        for segment in chain.segments {
            segmentByOrderedIndex[segment.index] = segment
        }

        for (index, point) in chain.orderedPoints.enumerated() {
            let plan = projector.project(point.coordinate).plan
            let seg = segmentByOrderedIndex[index]
            let row = [
                String(index + 1),
                csvEscape(point.name),
                String(format: "%.7f", point.coordinate.latitude),
                String(format: "%.7f", point.coordinate.longitude),
                String(format: "%.3f", plan.northing),
                String(format: "%.3f", plan.easting),
                seg.map { String(format: "%.2f", $0.length) } ?? "",
                seg.map { String(format: "%.2f", $0.cumulative) } ?? "",
                seg.map { String(format: "%.2f", $0.azimuth) } ?? "",
                seg.map { Geodesy.quadrantDescription($0.azimuth) } ?? "",
                csvEscape(point.note),
            ].joined(separator: ",")
            rows.append(row)
        }

        rows.append("")
        rows.append(String(format: "合计,,,,,,,,%.2f,,", chain.totalLength))
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    public static func writeFile(points: [SurveyPoint], chain: ChainResult, projection: ProjectionSetting, to url: URL) throws {
        let csv = makeCSV(points: points, chain: chain, projection: projection)
        var data = Data([0xEF, 0xBB, 0xBF]) // BOM
        data.append(Data(csv.utf8))
        try data.write(to: url)
    }
}
