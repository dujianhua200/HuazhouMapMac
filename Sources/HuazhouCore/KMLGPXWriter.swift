import Foundation

/// KML 2.2 导出（WGS84 经纬度，手机/Google Earth/多数 GIS 可直接打开）
public enum KMLWriter {

    public static func makeKML(points: [SurveyPoint], chain: ChainResult, documentName: String) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
          <name>\(escape(documentName))</name>

        """
        for point in chain.orderedPoints {
            xml += """
              <Placemark>
                <name>\(escape(point.name))</name>
                <description>\(escape(description(for: point)))</description>
                <Point><coordinates>\(coord(point.coordinate))</coordinates></Point>
              </Placemark>

            """
        }
        if chain.orderedPoints.count >= 2 {
            let line = chain.orderedPoints.map { coord($0.coordinate) }.joined(separator: " ")
            xml += """
              <Placemark>
                <name>线路</name>
                <LineString>
                  <tessellate>1</tessellate>
                  <coordinates>\(line)</coordinates>
                </LineString>
              </Placemark>

            """
        }
        xml += "</Document>\n</kml>\n"
        return xml
    }

    /// KML 坐标顺序为 经度,纬度[,高程]
    private static func coord(_ p: LatLon) -> String {
        String(format: "%.7f,%.7f,0", p.longitude, p.latitude)
    }

    private static func description(for point: SurveyPoint) -> String {
        var parts = [point.kind.displayName]
        if !point.note.isEmpty { parts.append(point.note) }
        parts.append(String(format: "%.7f, %.7f", point.coordinate.latitude, point.coordinate.longitude))
        return parts.joined(separator: " ｜ ")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    public static func writeFile(points: [SurveyPoint], chain: ChainResult, documentName: String, to url: URL) throws {
        try Data(makeKML(points: points, chain: chain, documentName: documentName).utf8).write(to: url)
    }
}

/// GPX 1.1 导出（航点 + 轨迹）
public enum GPXWriter {

    public static func makeGPX(points: [SurveyPoint], chain: ChainResult, name: String) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="HuazhouMap" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(name))</name></metadata>

        """
        for point in chain.orderedPoints {
            xml += """
              <wpt lat="\(format(point.coordinate.latitude))" lon="\(format(point.coordinate.longitude))">
                <name>\(escape(point.name))</name>
                <cmt>\(escape(point.note))</cmt>
              </wpt>

            """
        }
        if chain.orderedPoints.count >= 2 {
            xml += "  <trk>\n    <name>线路</name>\n    <trkseg>\n"
            for point in chain.orderedPoints {
                xml += """
                      <trkpt lat="\(format(point.coordinate.latitude))" lon="\(format(point.coordinate.longitude))"/>

                """
            }
            xml += "    </trkseg>\n  </trk>\n"
        }
        xml += "</gpx>\n"
        return xml
    }

    private static func format(_ v: Double) -> String { String(format: "%.7f", v) }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    public static func writeFile(points: [SurveyPoint], chain: ChainResult, name: String, to url: URL) throws {
        try Data(makeGPX(points: points, chain: chain, name: name).utf8).write(to: url)
    }
}
