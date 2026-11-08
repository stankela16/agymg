import Foundation

public enum RecommendedResourceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case mcp
    case skill
    case plugin

    public var displayLabel: String {
        switch self {
        case .mcp: return "MCP"
        case .skill: return "SKILL"
        case .plugin: return "PLUGIN"
        }
    }
}

public enum RecommendationPriority: String, Codable, Sendable, Hashable, Comparable {
    case high
    case medium
    case low

    private var rank: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    public static func < (lhs: RecommendationPriority, rhs: RecommendationPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct ResourceRecommendation: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var kind: RecommendedResourceKind
    public var reason: String
    public var priority: RecommendationPriority

    public var uniqueKey: String {
        "\(kind.rawValue):\(id)"
    }

    public init(
        id: String,
        name: String,
        kind: RecommendedResourceKind,
        reason: String,
        priority: RecommendationPriority = .medium
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.reason = reason
        self.priority = priority
    }
}

public struct ActiveWorkspaceContext: Codable, Sendable, Equatable {
    public var projectPath: String
    public var projectId: String?
    public var projectName: String?
    public var source: String
    public var updatedAt: Date

    public init(
        projectPath: String,
        projectId: String? = nil,
        projectName: String? = nil,
        source: String = "cli",
        updatedAt: Date = Date()
    ) {
        self.projectPath = projectPath
        self.projectId = projectId
        self.projectName = projectName
        self.source = source
        self.updatedAt = updatedAt
    }
}
