import Foundation

public struct ProjectProfile: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var path: String
    public var enabledMCPServerIds: Set<String>
    public var enabledSkillIds: Set<String>
    public var enabledPluginIds: Set<String>
    public var dismissedRecommendationKeys: Set<String>

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case enabledMCPServerIds
        case enabledSkillIds
        case enabledPluginIds
        case dismissedRecommendationKeys
    }

    public init(
        id: String,
        name: String,
        path: String,
        enabledMCPServerIds: Set<String> = [],
        enabledSkillIds: Set<String> = [],
        enabledPluginIds: Set<String> = [],
        dismissedRecommendationKeys: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.enabledMCPServerIds = enabledMCPServerIds
        self.enabledSkillIds = enabledSkillIds
        self.enabledPluginIds = enabledPluginIds
        self.dismissedRecommendationKeys = dismissedRecommendationKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        enabledMCPServerIds = try container.decodeIfPresent(Set<String>.self, forKey: .enabledMCPServerIds) ?? []
        enabledSkillIds = try container.decodeIfPresent(Set<String>.self, forKey: .enabledSkillIds) ?? []
        enabledPluginIds = try container.decodeIfPresent(Set<String>.self, forKey: .enabledPluginIds) ?? []
        dismissedRecommendationKeys = try container.decodeIfPresent(Set<String>.self, forKey: .dismissedRecommendationKeys) ?? []
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(path)
        hasher.combine(enabledMCPServerIds)
        hasher.combine(enabledSkillIds)
        hasher.combine(enabledPluginIds)
        hasher.combine(dismissedRecommendationKeys)
    }

    public static func == (lhs: ProjectProfile, rhs: ProjectProfile) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.path == rhs.path &&
        lhs.enabledMCPServerIds == rhs.enabledMCPServerIds &&
        lhs.enabledSkillIds == rhs.enabledSkillIds &&
        lhs.enabledPluginIds == rhs.enabledPluginIds &&
        lhs.dismissedRecommendationKeys == rhs.dismissedRecommendationKeys
    }
}
