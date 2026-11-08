import Foundation

public struct SkillDefinition: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var description: String
    public var category: String
    public var path: String
    public var origin: ResourceOrigin

    public init(
        id: String,
        name: String? = nil,
        description: String = "",
        category: String? = nil,
        path: String,
        origin: ResourceOrigin = .vault
    ) {
        self.id = id
        self.name = name ?? id
        self.description = description
        self.category = category ?? SkillDefinition.guessCategory(for: id)
        self.path = path
        self.origin = origin
    }

    public static func guessCategory(for id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("remotion") || lower.contains("video") || lower.contains("motion") || lower.contains("animate") || lower.contains("keyframes") {
            return "Video & Remotion"
        } else if lower.contains("swift") || lower.contains("ios") || lower.contains("widgets") || lower.contains("app-intents") || lower.contains("macos") {
            return "Swift & Apple"
        } else if lower.contains("review") || lower.contains("swarm") || lower.contains("refactor") || lower.contains("audit") || lower.contains("bug-hunt") {
            return "Multi-Agent & Review"
        } else if lower.contains("web") || lower.contains("react") || lower.contains("chrome") || lower.contains("a11y") || lower.contains("lcp") {
            return "Web & Frontend"
        } else if lower.contains("builtin") || lower.contains("antigravity") || lower.contains("customization") || lower.contains("workflow") {
            return "System & Engine"
        } else {
            return "Core & Tools"
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: SkillDefinition, rhs: SkillDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
