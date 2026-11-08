import Foundation

public struct PluginDefinition: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var description: String
    public var path: String
    public var hasMCP: Bool
    public var hasSkills: Bool

    public init(id: String, name: String? = nil, description: String = "", path: String, hasMCP: Bool = false, hasSkills: Bool = false) {
        self.id = id
        self.name = name ?? PluginDefinition.formatName(id)
        self.description = description
        self.path = path
        self.hasMCP = hasMCP
        self.hasSkills = hasSkills
    }

    public static func formatName(_ id: String) -> String {
        id.replacingOccurrences(of: "-plugin", with: "")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: PluginDefinition, rhs: PluginDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
