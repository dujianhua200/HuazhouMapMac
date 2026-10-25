import Foundation

/// 现场测点（默认即电杆/标定点）
public struct SurveyPoint: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var coordinate: LatLon
    public var note: String

    public init(id: UUID = UUID(), name: String, coordinate: LatLon, note: String = "") {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.note = note
    }
}

/// 连成一条链路的排序策略
public enum ChainMode: String, Codable, CaseIterable, Sendable {
    /// 按打点顺序连线
    case sequential
    /// 从首个点出发，贪心最近邻成链（适合野外乱序打点）
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
    /// 段号，从 1 开始
    public let index: Int
    public let fromName: String
    public let toName: String
    public let start: LatLon
    public let end: LatLon
    /// 段长（米）
    public let length: Double
    /// 起点到终点方位角（度）
    public let azimuth: Double
    /// 累计长度（米）
    public let cumulative: Double

    public var azimuthText: String {
        String(format: "%.1f°（%@）", azimuth, Geodesy.quadrantDescription(azimuth))
    }
}

public struct ChainResult: Sendable {
    /// 排序后的点位
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

    /// 按模式排出点位顺序
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
                    index: i,
                    fromName: a.name,
                    toName: b.name,
                    start: a.coordinate,
                    end: b.coordinate,
                    length: sol.distance,
                    azimuth: sol.initialAzimuth,
                    cumulative: cumulative
                )
            )
        }
        return ChainResult(orderedPoints: ordered, segments: segments, totalLength: cumulative)
    }
}
