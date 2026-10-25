import Foundation

/// DXF 导出选项
public struct DXFExportOptions: Sendable {
    public var projection: ProjectionSetting
    /// 电杆符号半径（米）
    public var poleRadius: Double
    /// 文字高度（米）
    public var textHeight: Double
    public var showPointName: Bool
    public var showSegmentLength: Bool

    public init(
        projection: ProjectionSetting = ProjectionSetting(),
        poleRadius: Double = 0.5,
        textHeight: Double = 1.5,
        showPointName: Bool = true,
        showSegmentLength: Bool = true
    ) {
        self.projection = projection
        self.poleRadius = poleRadius
        self.textHeight = textHeight
        self.showPointName = showPointName
        self.showSegmentLength = showSegmentLength
    }
}

/// 生成 AutoCAD R2000（AC1015）ASCII DXF。
/// 图层：电杆（圆）、杆号（文字）、线路（多段线）、段长（文字）。
/// 图纸坐标约定：DXF 的 X = 东坐标 easting，Y = 北坐标 northing。
public enum DXFWriter {

    public enum Layer {
        public static let pole = "电杆"
        public static let poleName = "杆号"
        public static let route = "线路"
        public static let lengthLabel = "段长标注"
    }

    public static func makeDXF(points: [SurveyPoint], chain: ChainResult, options: DXFExportOptions) -> String {
        let reference = points.first?.coordinate ?? LatLon(latitude: 0, longitude: 0)
        let projector = Projector(setting: options.projection, reference: reference)

        // 经纬度模式下单位为度，符号尺寸需换算，避免图形不可见
        let unitScale = options.projection.kind == .geographic ? 1.0 / 111_320.0 : 1.0
        let radius = options.poleRadius * unitScale
        let textHeight = options.textHeight * unitScale

        var lines: [String] = []
        var handle = 0x30
        func nextHandle() -> String {
            handle += 1
            return String(handle, radix: 16, uppercase: true)
        }
        func emit(_ code: Int, _ value: String) {
            lines.append(String(code))
            lines.append(value)
        }
        func num(_ v: Double) -> String {
            String(format: "%.4f", v)
        }

        // ---- HEADER ----
        emit(0, "SECTION"); emit(2, "HEADER")
        emit(9, "$ACADVER"); emit(1, "AC1015")
        emit(9, "$DWGCODEPAGE"); emit(3, "ANSI_936")
        emit(9, "$INSUNITS"); emit(70, "6")
        emit(9, "$HANDSEED"); emit(5, "FFFF")
        emit(0, "ENDSEC")

        // ---- TABLES ----
        emit(0, "SECTION"); emit(2, "TABLES")

        emit(0, "TABLE"); emit(2, "LTYPE"); emit(70, "1")
        emit(0, "LTYPE"); emit(2, "CONTINUOUS"); emit(70, "0")
        emit(3, "Solid line"); emit(72, "65"); emit(73, "0"); emit(40, "0.0")
        emit(0, "ENDTAB")

        let layers: [(String, Int)] = [
            ("0", 7),
            (Layer.pole, 3),
            (Layer.poleName, 7),
            (Layer.route, 1),
            (Layer.lengthLabel, 4),
        ]
        emit(0, "TABLE"); emit(2, "LAYER"); emit(70, String(layers.count))
        for (name, color) in layers {
            emit(0, "LAYER"); emit(2, name); emit(70, "0")
            emit(62, String(color)); emit(6, "CONTINUOUS")
        }
        emit(0, "ENDTAB")

        emit(0, "TABLE"); emit(2, "STYLE"); emit(70, "1")
        emit(0, "STYLE"); emit(2, "STANDARD"); emit(70, "0")
        emit(40, "0.0"); emit(41, "1.0"); emit(50, "0.0")
        emit(71, "0"); emit(42, "2.5"); emit(3, "txt"); emit(4, "")
        emit(0, "ENDTAB")

        emit(0, "ENDSEC")

        // ---- BLOCKS ----
        emit(0, "SECTION"); emit(2, "BLOCKS"); emit(0, "ENDSEC")

        // ---- ENTITIES ----
        emit(0, "SECTION"); emit(2, "ENTITIES")

        // 线路多段线
        if chain.orderedPoints.count >= 2 {
            emit(0, "LWPOLYLINE"); emit(5, nextHandle())
            emit(100, "AcDbEntity"); emit(8, Layer.route)
            emit(100, "AcDbPolyline")
            emit(90, String(chain.orderedPoints.count)); emit(70, "0")
            for p in chain.orderedPoints {
                let plan = projector.project(p.coordinate).plan
                emit(10, num(plan.easting)); emit(20, num(plan.northing))
            }
        }

        // 电杆与杆号
        for point in chain.orderedPoints {
            let plan = projector.project(point.coordinate).plan
            emit(0, "CIRCLE"); emit(5, nextHandle())
            emit(100, "AcDbEntity"); emit(8, Layer.pole)
            emit(100, "AcDbCircle")
            emit(10, num(plan.easting)); emit(20, num(plan.northing)); emit(30, "0.0")
            emit(40, num(radius))

            if options.showPointName && !point.name.isEmpty {
                emit(0, "TEXT"); emit(5, nextHandle())
                emit(100, "AcDbEntity"); emit(8, Layer.poleName)
                emit(100, "AcDbText")
                emit(10, num(plan.easting + radius * 1.2))
                emit(20, num(plan.northing + radius * 0.6))
                emit(30, "0.0")
                emit(40, num(textHeight))
                emit(1, point.name)
                emit(50, "0.0"); emit(7, "STANDARD")
            }
        }

        // 段长标注（放在链路中点偏移处）
        if options.showSegmentLength {
            for segment in chain.segments {
                let mid = LatLon(
                    latitude: (segment.start.latitude + segment.end.latitude) / 2,
                    longitude: (segment.start.longitude + segment.end.longitude) / 2
                )
                let plan = projector.project(mid).plan
                emit(0, "TEXT"); emit(5, nextHandle())
                emit(100, "AcDbEntity"); emit(8, Layer.lengthLabel)
                emit(100, "AcDbText")
                emit(10, num(plan.easting))
                emit(20, num(plan.northing + textHeight * 0.8))
                emit(30, "0.0")
                emit(40, num(textHeight * 0.8))
                emit(1, String(format: "%.1fm", segment.length))
                emit(50, "0.0"); emit(7, "STANDARD")
            }
        }

        emit(0, "ENDSEC")
        emit(0, "EOF")

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// 文字按 GB18030 编码，保证中文图层名/杆号在国产 CAD 中正常显示
    public static func gb18030Data(_ text: String) -> Data {
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let data = text.data(using: encoding) { return data }
        let sanitized = text.map { char -> Character in
            String(char).data(using: encoding) == nil ? "?" : char
        }
        return String(sanitized).data(using: encoding) ?? Data(text.utf8)
    }

    public static func writeFile(points: [SurveyPoint], chain: ChainResult, options: DXFExportOptions, to url: URL) throws {
        let text = makeDXF(points: points, chain: chain, options: options)
        try gb18030Data(text).write(to: url)
    }
}
