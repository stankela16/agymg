import SwiftUI
import AppKit

public struct RuntimeManifestPreviewView: View {
    public let project: ProjectProfile
    public let state: AppState

    @State var manifestJSON: String

    public init(project: ProjectProfile, state: AppState) {
        self.project = project
        self.state = state
        _manifestJSON = State(initialValue: Self.generateManifestJSON(project: project, servers: state.servers))
    }

    private static let sensitiveParamKeys: Set<String> = [
        "token", "access_token", "api_key", "apikey", "key", "secret", "password", "auth"
    ]

    private static func redactURLSecrets(_ rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL),
              let items = components.queryItems, !items.isEmpty else {
            return rawURL
        }
        var changed = false
        components.queryItems = items.map { item in
            if let val = item.value, !val.isEmpty,
               sensitiveParamKeys.contains(item.name.lowercased()) {
                changed = true
                return URLQueryItem(name: item.name, value: "<REDACTED>")
            }
            return item
        }
        return changed ? (components.string ?? rawURL) : rawURL
    }

    private static func redactArgsSecrets(_ args: [Any]) -> [Any] {
        let sensitiveFlags: Set<String> = ["--api-key", "--apikey", "--token", "--access-token", "--secret", "--password"]
        var redacted: [Any] = []
        var redactNext = false
        for rawArg in args {
            guard let str = rawArg as? String else {
                redacted.append(rawArg)
                redactNext = false
                continue
            }
            if redactNext {
                redacted.append(str.isEmpty ? str : "<REDACTED>")
                redactNext = false
                continue
            }
            let lower = str.lowercased()
            if sensitiveFlags.contains(lower) {
                redacted.append(str)
                redactNext = true
            } else if let eqIndex = str.firstIndex(of: "=") {
                let prefix = String(str[..<eqIndex])
                let suffix = String(str[str.index(after: eqIndex)...])
                if sensitiveFlags.contains(prefix.lowercased()) && !suffix.isEmpty {
                    redacted.append("\(prefix)=<REDACTED>")
                } else {
                    redacted.append(str)
                }
            } else {
                redacted.append(str)
            }
        }
        return redacted
    }

    static func generateManifestJSON(project: ProjectProfile, servers: [MCPServerDefinition]) -> String {
        let serverMap = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
        var projectServers: [String: [String: Any]] = [:]

        for serverId in project.enabledMCPServerIds.sorted() where PathConstants.isSafeResourceId(serverId) {
            guard let server = serverMap[serverId] else { continue }
            var raw = server.config.mapValues { $0.toAny() }
            raw.removeValue(forKey: "disabled")

            if let envDict = raw["env"] as? [String: Any] {
                var redactedEnv: [String: Any] = [:]
                for (k, v) in envDict {
                    if let s = v as? String, !s.isEmpty {
                        redactedEnv[k] = "<REDACTED>"
                    } else {
                        redactedEnv[k] = v
                    }
                }
                raw["env"] = redactedEnv
            }

            if let headersDict = raw["headers"] as? [String: Any] {
                var redactedHeaders: [String: Any] = [:]
                for (k, v) in headersDict {
                    if let s = v as? String, !s.isEmpty {
                        redactedHeaders[k] = "<REDACTED>"
                    } else {
                        redactedHeaders[k] = v
                    }
                }
                raw["headers"] = redactedHeaders
            }

            if let argsArray = raw["args"] as? [Any] {
                raw["args"] = redactArgsSecrets(argsArray)
            }

            if let serverUrl = raw["serverUrl"] as? String {
                raw["serverUrl"] = redactURLSecrets(serverUrl)
            }
            if let url = raw["url"] as? String {
                raw["url"] = redactURLSecrets(url)
            }

            projectServers[serverId] = raw
        }

        let payload: [String: Any] = ["mcpServers": projectServers]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\n  \"mcpServers\" : {\n\n  }\n}"
    }

    func updateManifest() {
        manifestJSON = Self.generateManifestJSON(project: project, servers: state.servers)
    }

    func handleRegenerate() {
        state.triggerProjectSync(project: project)
        updateManifest()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Runtime Manifest Preview")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.ink)
                    Text(".agents/plugins/agy-manager/mcp_config.json")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(DesignTokens.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(manifestJSON, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Copy runtime manifest JSON to clipboard")

                    Button {
                        handleRegenerate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Regenerate")
                        }
                        .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Regenerate .agents/plugins/agy-manager configuration")
                }
            }

            // Dark JSON box
            ScrollView(.horizontal, showsIndicators: false) {
                Text(manifestJSON)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x81C784))
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x07110C))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x1A2E24), lineWidth: 1))
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
        .task(id: project) {
            updateManifest()
        }
        .task(id: state.servers) {
            updateManifest()
        }
    }
}
