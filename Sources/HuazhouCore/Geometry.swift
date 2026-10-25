import Foundation

/// 折线/多边形的几何量
public enum Geometry {

    /// 折线总长（米）
    public static func polylineLength(_ points: [LatLon]) -> Double {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { $0 + Geodesy.distance($1.0, $1.1) }
    }

    /// 多边形面积（平方米）。以质心为原点投影到局部平面后按鞋带公式计算，
    /// 对公里级范围误差可忽略。
    public static func polygonArea(_ ring: [LatLon]) -> Double {
        guard ring.count >= 3 else { return 0 }
        let centroid = LatLon(
            latitude: ring.map(\.latitude).reduce(0, +) / Double(ring.count),
            longitude: ring.map(\.longitude).reduce(0, +) / Double(ring.count)
        )
        let projector = Projector(setting: ProjectionSetting(kind: .localPlane), reference: centroid)
        let xy = ring.map { projector.project($0).plan }
        var sum = 0.0
        for i in 0..<xy.count {
            let p = xy[i]
            let q = xy[(i + 1) % xy.count]
            sum += p.easting * q.northing - q.easting * p.northing
        }
        return abs(sum) / 2
    }

    /// 闭合环的周长（米）
    public static func ringPerimeter(_ ring: [LatLon]) -> Double {
        guard ring.count >= 2 else { return 0 }
        let closed = ring + [ring[0]]
        return polylineLength(closed)
    }

    /// 点是否落在多边形内（射线法，局部平面近似）
    public static func contains(_ point: LatLon, in ring: [LatLon]) -> Bool {
        guard ring.count >= 3 else { return false }
        let projector = Projector(setting: ProjectionSetting(kind: .localPlane), reference: ring[0])
        let p = projector.project(point).plan
        let poly = ring.map { projector.project($0).plan }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.northing > p.northing) != (b.northing > p.northing) {
                let t = (p.northing - a.northing) / (b.northing - a.northing)
                if p.easting < a.easting + t * (b.easting - a.easting) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
