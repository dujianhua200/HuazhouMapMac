import Foundation

public enum ImportError: LocalizedError {
    case emptyFile
    case noCoordinateColumn
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .emptyFile: return "文件为空"
        case .noCoordinateColumn: return "找不到经纬度列（需要 纬度/经度 或 lat/lon 列）"
        case .unreadable: return "文件编码无法识别"
        }
    }
}

/// CSV 点表导入。支持本程序导出的点表，也支持常见"点名,纬度,经度"格式。
public enum CSVImporter {

    public static func parse(data: Data, defaultKind: ObjectKind = .pole) throws -> [SurveyPoint] {
        let text = decode(data)
        let rows = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { splitFields($0) }
        guard !rows.isEmpty else { throw ImportError.emptyFile }

        var nameIndex: Int?
        var latIndex: Int?
        var lonIndex: Int?
        var noteIndex: Int?
        var dataRows = rows

        if let header = detectHeader(rows[0]) {
            nameIndex = header.name
            latIndex = header.lat
            lonIndex = header.lon
            noteIndex = header.note
            dataRows = Array(rows.dropFirst())
        }

        if latIndex == nil || lonIndex == nil {
            guard let detected = detectByRange(dataRows) else { throw ImportError.noCoordinateColumn }
            latIndex = detected.lat
            lonIndex = detected.lon
        }

        // 无表头时：把非数值列依次当点名、备注
        if nameIndex == nil || noteIndex == nil {
            let textColumns = textColumnIndexes(dataRows, excluding: [latIndex!, lonIndex!])
            if nameIndex == nil, let first = textColumns.first { nameIndex = first }
            if noteIndex == nil, textColumns.count > 1 { noteIndex = textColumns[1] }
        }

        var result: [SurveyPoint] = []
        var counter = 0
        for row in dataRows {
            guard row.count > max(latIndex!, lonIndex!) else { continue }
            guard let lat = Double(row[latIndex!]), let lon = Double(row[lonIndex!]) else { continue }
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { continue }
            counter += 1
            let name = nameIndex.flatMap { $0 < row.count ? row[$0] : nil }.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(format: "%@%03d", defaultKind.namePrefix, counter)
            let note = noteIndex.flatMap { $0 < row.count ? row[$0] : "" } ?? ""
            result.append(SurveyPoint(name: name, coordinate: LatLon(latitude: lat, longitude: lon), note: note, kind: defaultKind))
        }
        guard !result.isEmpty else { throw ImportError.noCoordinateColumn }
        return result
    }

    // MARK: - 内部

    private static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        }
        if let s = String(data: data, encoding: .utf8), !s.isEmpty { return s }
        let gbk = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        return String(data: data, encoding: gbk) ?? ""
    }

    /// 支持双引号包裹与 "" 转义
    private static func splitFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character?
        while let ch = pending ?? iterator.next() {
            pending = nil
            if ch == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
                continue
            }
            if ch == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(ch)
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private static let nameKeys = ["点名", "名称", "杆号", "编号", "name", "label", "id"]
    private static let latKeys = ["纬度", "北纬", "lat", "latitude"]
    private static let lonKeys = ["经度", "东经", "lon", "lng", "long", "longitude"]
    private static let noteKeys = ["备注", "说明", "note", "remark", "comment"]

    private static func detectHeader(_ row: [String]) -> (name: Int?, lat: Int?, lon: Int?, note: Int?)? {
        var name: Int?, lat: Int?, lon: Int?, note: Int?
        for (i, raw) in row.enumerated() {
            let h = raw.lowercased()
            if lat == nil, latKeys.contains(where: { h.contains($0) }) { lat = i }
            else if lon == nil, lonKeys.contains(where: { h.contains($0) }) { lon = i }
            else if name == nil, nameKeys.contains(where: { h.contains($0) }) { name = i }
            else if note == nil, noteKeys.contains(where: { h.contains($0) }) { note = i }
        }
        // 至少要能定位纬或经，否则不当作表头
        guard lat != nil || lon != nil else { return nil }
        // 表头里若含"北坐标/东坐标"这类投影坐标，避免误判为经纬度
        let hasProjected = row.contains { $0.contains("坐标") }
        if hasProjected {
            let hasDegreeHeader = row.contains { $0.contains("纬") || $0.contains("经") }
            if !hasDegreeHeader { return nil }
        }
        return (name, lat, lon, note)
    }

    private static func detectByRange(_ rows: [[String]]) -> (lat: Int, lon: Int)? {
        guard let first = rows.first else { return nil }
        var latIdx: Int?
        var lonIdx: Int?
        for (i, field) in first.enumerated() {
            guard let value = Double(field) else { continue }
            if (73.0...136.0).contains(value), lonIdx == nil { lonIdx = i }
            else if (3.0...54.0).contains(value), latIdx == nil { latIdx = i }
        }
        guard let lat = latIdx, let lon = lonIdx, lat != lon else { return nil }
        return (lat, lon)
    }

    /// 找出"文本型"列（非数值、非空），用于无表头时定位点名/备注
    private static func textColumnIndexes(_ rows: [[String]], excluding: Set<Int>) -> [Int] {
        guard let first = rows.first else { return [] }
        var result: [Int] = []
        for (i, field) in first.enumerated() {
            guard !excluding.contains(i), !field.isEmpty, Double(field) == nil else { continue }
            result.append(i)
        }
        return result
    }
}

/// KML 导入：读取 Placemark 中的 Point 与 LineString
public enum KMLImporter {

    public static func parse(data: Data, defaultKind: ObjectKind = .pole) throws -> [SurveyPoint] {
        let delegate = KMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? ImportError.unreadable
        }
        guard !delegate.found.isEmpty else { throw ImportError.noCoordinateColumn }

        var result: [SurveyPoint] = []
        var counter = 0
        for item in delegate.found {
            for coordinate in item.coordinates {
                counter += 1
                let name = item.name.isEmpty
                    ? String(format: "%@%03d", defaultKind.namePrefix, counter)
                    : (item.coordinates.count > 1 ? "\(item.name)-\(counter)" : item.name)
                result.append(
                    SurveyPoint(name: name, coordinate: coordinate, note: "", kind: defaultKind)
                )
            }
        }
        return result
    }
}

private final class KMLParserDelegate: NSObject, XMLParserDelegate {
    struct Item {
        var name: String = ""
        var coordinates: [LatLon] = []
    }

    private(set) var found: [Item] = []
    private var current = Item()
    private var inPlacemark = false
    private var buffer = ""
    private var collectingName = false
    private var collectingCoordinates = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let tag = localName(elementName)
        switch tag {
        case "placemark":
            inPlacemark = true
            current = Item()
        case "name":
            collectingName = inPlacemark
            buffer = ""
        case "coordinates":
            collectingCoordinates = true
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingName || collectingCoordinates { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let tag = localName(elementName)
        switch tag {
        case "name":
            if collectingName {
                current.name = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                collectingName = false
            }
        case "coordinates":
            collectingCoordinates = false
            let coords = buffer
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
                .compactMap { token -> LatLon? in
                    let parts = token.split(separator: ",")
                    guard parts.count >= 2,
                          let lon = Double(parts[0]),
                          let lat = Double(parts[1]),
                          (-90...90).contains(lat), (-180...180).contains(lon)
                    else { return nil }
                    return LatLon(latitude: lat, longitude: lon)
                }
            current.coordinates.append(contentsOf: coords)
        case "placemark":
            if inPlacemark && !current.coordinates.isEmpty { found.append(current) }
            inPlacemark = false
        default:
            break
        }
    }

    private func localName(_ element: String) -> String {
        element.split(separator: ":").last.map(String.init)?.lowercased() ?? element.lowercased()
    }
}
