import SwiftUI

public struct MenuBarServerRow: View {
    @Bindable var state: AppState
    let server: MCPServerDefinition
    let projectId: String?
    @State private var isHovered: Bool = false

    public init(state: AppState, server: MCPServerDefinition, projectId: String? = nil) {
        self.state = state
        self.server = server
        self.projectId = projectId
    }

    private var project: ProjectProfile? {
        guard let projectId else { return nil }
        return state.projects.first(where: { $0.id == projectId })
    }

    private var isGlobal: Bool {
        state.globalServerIds.contains(server.id)
    }

    private var isProjectEnabled: Bool {
        project?.enabledMCPServerIds.contains(server.id) ?? false
    }

    private var isEnabled: Bool {
        if projectId != nil {
            return isGlobal || isProjectEnabled
        } else {
            return isGlobal
        }
    }

    private var isInheritedGlobal: Bool {
        projectId != nil && isGlobal
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(isEnabled ? Color.green : DesignTokens.inkTertiary.opacity(0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(server.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.ink)
                        .lineLimit(1)

                    if isInheritedGlobal {
                        Text("GLOBAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.tierOrange)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.tierOrange.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Inherited from Global Core (active across all workspaces)")
                    } else if projectId != nil && isProjectEnabled {
                        Text("PROJECT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.secondary.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Locally enabled for this project")
                    }
                }

                Text(serverSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .lineLimit(1)
            }

            Spacer()

            toggleControl
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(isHovered ? DesignTokens.surfaceContainerHigh : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var serverSubtitle: String {
        let base = server.summary.isEmpty ? (server.command ?? server.id) : server.summary
        if isInheritedGlobal {
            return "Inherited • \(base)"
        }
        return base
    }

    @ViewBuilder
    private var toggleControl: some View {
        if isInheritedGlobal {
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(true)
                .help("\(server.name) is enabled globally via Global Core (inherited)")
        } else if let pId = projectId {
            Toggle("", isOn: Binding(
                get: { isProjectEnabled },
                set: { _ in state.toggleProjectServer(projectId: pId, serverId: server.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(isProjectEnabled ? "Disable \(server.name) for this project" : "Enable \(server.name) for project \(project?.name ?? "")")
        } else {
            Toggle("", isOn: Binding(
                get: { isGlobal },
                set: { _ in state.toggleGlobalServer(id: server.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(isGlobal ? "Disable \(server.name) in Global Core" : "Enable \(server.name) in Global Core")
        }
    }
}
