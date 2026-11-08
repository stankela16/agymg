import Foundation

public struct ProjectProfile: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var path: String
    public var enabledMCPServerIds: Set<String>
    public var enabledSkillIds: Set<String>
    public var enabledPluginIds: Set<String>

    public init(
        id: String,
        name: String,
        path: String,
        enabledMCPServerIds: Set<String> = [],
        enabledSkillIds: Set<String> = [],
        enabledPluginIds: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.enabledMCPServerIds = enabledMCPServerIds
        self.enabledSkillIds = enabledSkillIds
        self.enabledPluginIds = enabledPluginIds
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(path)
        hasher.combine(enabledMCPServerIds)
        hasher.combine(enabledSkillIds)
        hasher.combine(enabledPluginIds)
    }

    public static func == (lhs: ProjectProfile, rhs: ProjectProfile) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.path == rhs.path &&
        lhs.enabledMCPServerIds == rhs.enabledMCPServerIds &&
        lhs.enabledSkillIds == rhs.enabledSkillIds &&
        lhs.enabledPluginIds == rhs.enabledPluginIds
    }
}
