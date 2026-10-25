import Foundation

/// 工程文件（.hzmap，JSON）
public struct SurveyProject: Codable, Sendable {
    public var name: String
    public var points: [SurveyPoint]
    public var chainMode: ChainMode
    public var projection: ProjectionSetting
    public var createdAt: Date
    /// 是否把底图显示坐标按 GCJ-02 纠偏（国内底图对齐用）
    public var applyGCJCorrection: Bool

    public init(
        name: String = "未命名工程",
        points: [SurveyPoint] = [],
        chainMode: ChainMode = .sequential,
        projection: ProjectionSetting = ProjectionSetting(),
        createdAt: Date = Date(),
        applyGCJCorrection: Bool = false
    ) {
        self.name = name
        self.points = points
        self.chainMode = chainMode
        self.projection = projection
        self.createdAt = createdAt
        self.applyGCJCorrection = applyGCJCorrection
    }

    enum CodingKeys: String, CodingKey {
        case name, points, chainMode, projection, createdAt, applyGCJCorrection
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名工程"
        points = try c.decodeIfPresent([SurveyPoint].self, forKey: .points) ?? []
        chainMode = try c.decodeIfPresent(ChainMode.self, forKey: .chainMode) ?? .sequential
        projection = try c.decodeIfPresent(ProjectionSetting.self, forKey: .projection) ?? ProjectionSetting()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        applyGCJCorrection = try c.decodeIfPresent(Bool.self, forKey: .applyGCJCorrection) ?? false
    }

    public var chain: ChainResult {
        ChainBuilder.build(points, mode: chainMode)
    }

    /// 按对象类型生成下一个点名，如电杆 G001、人孔 R001
    public func nextPointName(for kind: ObjectKind = .pole) -> String {
        let prefix = kind.namePrefix
        let existing = Set(points.filter { $0.kind == kind }.map(\.name))
        var index = existing.count + 1
        while existing.contains(String(format: "%@%03d", prefix, index)) { index += 1 }
        return String(format: "%@%03d", prefix, index)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func load(from data: Data) throws -> SurveyProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SurveyProject.self, from: data)
    }
}
