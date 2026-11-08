import Foundation

public enum NavigationSection: Hashable, Sendable {
    case masterVault
    case globalCore
    case systemBuiltins
    case plugins
    case project(String)
    case skillEditor
    case syncLogs
    case settings
}

public enum DeletionTarget: Identifiable, Sendable {
    case server(MCPServerDefinition)
    case skill(SkillDefinition)
    case plugin(PluginDefinition)

    public var id: String {
        switch self {
        case .server(let s): return "server-\(s.id)"
        case .skill(let s): return "skill-\(s.id)"
        case .plugin(let p): return "plugin-\(p.id)"
        }
    }

    public var name: String {
        switch self {
        case .server(let s): return s.name
        case .skill(let s): return s.name
        case .plugin(let p): return p.name
        }
    }

    public var typeTitle: String {
        switch self {
        case .server: return "MCP Server"
        case .skill: return "Skill"
        case .plugin: return "Plugin"
        }
    }
}
