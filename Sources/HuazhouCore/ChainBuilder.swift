import Foundation

/// 现场测点
public struct SurveyPoint: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var coordinate: LatLon
    public var note: String
    public var kind: ObjectKind

    public init(
        id: UUID = UUID(),
        name: String,
        coordinate: LatLon,
        note: String = "",
        kind: ObjectKind = .pole
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.note = note
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case id, name, coordinate, note, kind
    }

    /// 旧版工程文件没有 kind 字段，解码时回落为电杆
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        coordinate = try container.decode(LatLon.self, forKey: .coordinate)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        kind = try container.decodeIfPresent(ObjectKind.self, forKey: .kind) ?? .pole
    }
}

/// 连成一条链路的排序策略
public enum ChainMode: String, Codable, CaseIterable, Sendable {
    case sequential
    case nearestNeighbor

    public var displayName: String {
        switch self {
        case .sequential: return "按打点顺序"
        case .nearestNeighbor: return "自动最近邻成链"
        }
    }
}

public struct ChainSegment: Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let fromName: String
    public let toName: String
    public let start: LatLon
    public let end: LatLon
    public let length: Double
    public let azimuth: Double
    public let cumulative: Double

    public var azimuthText: String {
        String(format: "%.1f°（%@）", azimuth, Geodesy.quadrantDescription(azimuth))
    }
}

public struct ChainResult: Sendable {
    public let orderedPoints: [SurveyPoint]
    public let segments: [ChainSegment]
    public let totalLength: Double

    public var pointCount: Int { orderedPoints.count }
    public var averageSegment: Double {
        segments.isEmpty ? 0 : totalLength / Double(segments.count)
    }
    public var isEmpty: Bool { segments.isEmpty }
}

public enum ChainBuilder {

    public static func order(_ points: [SurveyPoint], mode: ChainMode) -> [SurveyPoint] {
        switch mode {
        case .sequential:
            return points
        case .nearestNeighbor:
            guard points.count > 2 else { return points }
            var remaining = points
            var result: [SurveyPoint] = [remaining.removeFirst()]
            var cursor = result[0].coordinate
            while !remaining.isEmpty {
                var bestIndex = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for (i, candidate) in remaining.enumerated() {
                    let d = Geodesy.distance(cursor, candidate.coordinate)
                    if d < bestDistance {
                        bestDistance = d
                        bestIndex = i
                    }
                }
                let next = remaining.remove(at: bestIndex)
                result.append(next)
                cursor = next.coordinate
            }
            return result
        }
    }

    public static func build(_ points: [SurveyPoint], mode: ChainMode) -> ChainResult {
        let ordered = order(points, mode: mode)
        guard ordered.count >= 2 else {
            return ChainResult(orderedPoints: ordered, segments: [], totalLength: 0)
        }
        var segments: [ChainSegment] = []
        segments.reserveCapacity(ordered.count - 1)
        var cumulative = 0.0
        for i in 1..<ordered.count {
            let a = ordered[i - 1]
            let b = ordered[i]
            let sol = Geodesy.inverse(a.coordinate, b.coordinate)
            cumulative += sol.distance
            segments.append(
                ChainSegment(
                    index: i, fromName: a.name, toName: b.name,
                    start: a.coordinate, end: b.coordinate,
                    length: sol.distance, azimuth: sol.initialAzimuth, cumulative: cumulative
                )
            )
        }
        return ChainResult(orderedPoints: ordered, segments: segments, totalLength: cumulative)
    }
}
