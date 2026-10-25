import Foundation

/// 测点对象类型（对应奥维的"对象类型"概念）
public enum ObjectKind: String, Codable, CaseIterable, Sendable {
    case pole        // 电杆
    case manhole     // 人孔
    case joint       // 接头盒
    case marker      // 标石/标桩
    case crossing    // 跨越点
    case station     // 基站/机房
    case other       // 其他

    public var displayName: String {
        switch self {
        case .pole: return "电杆"
        case .manhole: return "人孔"
        case .joint: return "接头盒"
        case .marker: return "标石"
        case .crossing: return "跨越点"
        case .station: return "机房"
        case .other: return "其他"
        }
    }

    /// 点名默认前缀
    public var namePrefix: String {
        switch self {
        case .pole: return "G"
        case .manhole: return "R"
        case .joint: return "J"
        case .marker: return "B"
        case .crossing: return "K"
        case .station: return "F"
        case .other: return "P"
        }
    }

    /// DXF 图层名
    public var layerName: String { displayName }
}
