import Foundation

/// 线路加密：按档距在两点之间等间距插点
public enum RoutePlanner {

    /// 在 from→to 之间按 spacing 米等间距插点（不含两端）。
    /// 距终点不足半个档距时不再插点，避免生成几乎重合的点。
    /// 短段采用经纬度线性插值，100 m 段误差 < 1 cm，杆档量级足够。
    public static func interpolate(from: LatLon, to: LatLon, spacing: Double) -> [LatLon] {
        guard spacing > 0.1 else { return [] }
        let distance = Geodesy.distance(from, to)
        guard distance > spacing * 1.5 else { return [] }

        var result: [LatLon] = []
        var index = 1
        while Double(index) * spacing <= distance - spacing * 0.5 {
            let t = Double(index) * spacing / distance
            result.append(
                LatLon(
                    latitude: from.latitude + (to.latitude - from.latitude) * t,
                    longitude: from.longitude + (to.longitude - from.longitude) * t
                )
            )
            index += 1
        }
        return result
    }

    /// 对整条链路逐段插点，返回插入的新点（保持沿线顺序）
    public static func densify(
        chain: ChainResult,
        spacing: Double,
        namedBy prefix: String = "Z",
        kind: ObjectKind = .pole
    ) -> [SurveyPoint] {
        let ordered = chain.orderedPoints
        guard ordered.count >= 2 else { return [] }
        var inserted: [SurveyPoint] = []
        var counter = 1
        for i in 1..<ordered.count {
            let a = ordered[i - 1].coordinate
            let b = ordered[i].coordinate
            for coordinate in interpolate(from: a, to: b, spacing: spacing) {
                inserted.append(
                    SurveyPoint(
                        name: String(format: "%@%03d", prefix, counter),
                        coordinate: coordinate,
                        note: "等间距插入（档距 \(Int(spacing)) m）",
                        kind: kind
                    )
                )
                counter += 1
            }
        }
        return inserted
    }

    /// 估算按当前档距会插入多少个点（与 interpolate 判定规则一致）
    public static func estimatedInsertCount(chain: ChainResult, spacing: Double) -> Int {
        guard spacing > 0.1 else { return 0 }
        return chain.segments.reduce(0) { sum, segment in
            guard segment.length > spacing * 1.5 else { return sum }
            let n = Int(floor((segment.length - spacing * 0.5) / spacing))
            return sum + max(0, n)
        }
    }
}
