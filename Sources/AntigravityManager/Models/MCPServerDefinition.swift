import Foundation

public struct MCPServerDefinition: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var category: String
    public var config: [String: JSONValue]

    public init(id: String, name: String? = nil, category: String? = nil, config: [String: JSONValue]) {
        self.id = id
        self.name = name ?? id
        self.category = category ?? MCPServerDefinition.guessCategory(for: id)
        self.config = config
    }

    public var serverUrl: String? {
        config["serverUrl"]?.stringValue
    }

    public var command: String? {
        config["command"]?.stringValue
    }

    public var isRemote: Bool {
        serverUrl != nil
    }

    public var summary: String {
        if let url = serverUrl {
            return url
        }
        if let cmd = command {
            if let args = config["args"]?.arrayValue {
                let stringArgs = args.compactMap(\.stringValue)
                if let targetArg = stringArgs.first(where: { !$0.hasPrefix("-") }) ?? stringArgs.first {
                    return "\(cmd) \(targetArg)"
                }
            }
            return cmd
        }
        return "Custom MCP Server"
    }

    public static func guessCategory(for id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("supabase") || lower.contains("db") || lower.contains("sql") {
            return "Database"
        } else if lower.contains("git") {
            return "Git"
        } else if lower.contains("cloud") || lower.contains("digitalocean") || lower.contains("vercel") || lower.contains("netlify") || lower.contains("gcloud") {
            return "Cloud"
        } else if lower.contains("umami") || lower.contains("posthog") || lower.contains("analytics") {
            return "Analytics"
        } else if lower.contains("brevo") || lower.contains("mail") || lower.contains("telegram") {
            return "Communication"
        } else if lower.contains("polar") {
            return "Payments"
        } else if lower.contains("figma") {
            return "Design"
        } else {
            return "Tools"
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MCPServerDefinition, rhs: MCPServerDefinition) -> Bool {
        lhs.id == rhs.id
    }
}
