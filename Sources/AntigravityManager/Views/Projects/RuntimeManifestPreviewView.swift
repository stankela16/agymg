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

    private struct ManifestPreview: Encodable {
        struct ServerPreview: Encodable {
            let command: String
            let args: [String]
            let active: Bool
        }
        let schemaVersion: String
        let scope: String
        let masterVaultRef: String
        let servers: [String: ServerPreview]
        let activeSkills: [String]
    }

    static func generateManifestJSON(project: ProjectProfile, servers: [MCPServerDefinition]) -> String {
        let enabled = servers.filter { project.enabledMCPServerIds.contains($0.id) }
        var serverDict: [String: ManifestPreview.ServerPreview] = [:]
        for s in enabled {
            let argsList = s.config["args"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            serverDict[s.id] = ManifestPreview.ServerPreview(
                command: s.command ?? "npx",
                args: argsList,
                active: true
            )
        }
        let preview = ManifestPreview(
            schemaVersion: "2.1.0",
            scope: project.name,
            masterVaultRef: "~/.gemini/manager-vault/",
            servers: serverDict,
            activeSkills: Array(project.enabledSkillIds).sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(preview),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\n  \"schemaVersion\": \"2.1.0\",\n  \"scope\": \"\(project.name)\"\n}"
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
