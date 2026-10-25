import Foundation

/// 工程文件（.hzmap，JSON）
public struct SurveyProject: Codable, Sendable {
    public var name: String
    public var points: [SurveyPoint]
    public var chainMode: ChainMode
    public var projection: ProjectionSetting
    public var createdAt: Date

    public init(
        name: String = "未命名工程",
        points: [SurveyPoint] = [],
        chainMode: ChainMode = .sequential,
        projection: ProjectionSetting = ProjectionSetting(),
        createdAt: Date = Date()
    ) {
        self.name = name
        self.points = points
        self.chainMode = chainMode
        self.projection = projection
        self.createdAt = createdAt
    }

    public var chain: ChainResult {
        ChainBuilder.build(points, mode: chainMode)
    }

    /// 自动生成下一个点名，如 G001
    public func nextPointName(prefix: String = "G") -> String {
        var used = Set(points.map { $0.name })
        var i = points.count + 1
        while used.contains(String(format: "%@%03d", prefix, i)) { i += 1 }
        let candidate = String(format: "%@%03d", prefix, i)
        used.insert(candidate)
        return candidate
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
