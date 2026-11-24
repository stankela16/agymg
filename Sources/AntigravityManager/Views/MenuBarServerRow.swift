import SwiftUI
import AppKit

public struct MenuBarServerRow: View {
    @Bindable var state: AppState
    let server: MCPServerDefinition
    let projectId: String?
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    @State private var isHovered: Bool = false
    @State private var isCopied: Bool = false

    public init(
        state: AppState,
        server: MCPServerDefinition,
        projectId: String? = nil,
        isExpanded: Bool = false,
        onToggleExpand: (() -> Void)? = nil
    ) {
        self.state = state
        self.server = server
        self.projectId = projectId
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                rowHeaderButton
                toggleControl
            }

            if isExpanded {
                expandedDetailView
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(isExpanded ? DesignTokens.surfaceContainerLow : (isHovered ? DesignTokens.surfaceContainerHigh : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isExpanded ? DesignTokens.cardBorder : Color.clear, lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var rowHeaderButton: some View {
        if let onToggleExpand {
            Button(action: onToggleExpand) {
                headerLabel
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(server.name) details" : "Inspect \(server.name) endpoint and health")
        } else {
            headerLabel
        }
    }

    private var headerLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(statusDotColor)
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

                    if onToggleExpand != nil && (isHovered || isExpanded) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignTokens.inkTertiary)
                    }

                    if isEnabled, state.contextUsage.scannedSessionsCount > 0 {
                        let stats = state.contextUsage.mcpStats(for: server.id)
                        let calls = projectId.map { stats.calls(inProject: $0) } ?? stats.totalCalls30d
                        Text("\(calls)x")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(calls == 0 ? DesignTokens.tierOrange : DesignTokens.inkTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(calls == 0 ? DesignTokens.tierOrange.opacity(0.12) : DesignTokens.surfaceContainer)
                            .clipShape(Capsule())
                            .help(calls == 0
                                  ? "Dormant: 0 calls in the last 30 days (\(stats.totalCalls30d)x across all projects)"
                                  : "\(calls) calls in the last 30 days")
                    }
                }

                if !isExpanded {
                    Text(serverSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var statusDotColor: Color {
        if let health = state.mcpHealthByServerId[server.id], health.state == .error {
            return DesignTokens.Colors.statusError
        }
        if isEnabled {
            if let health = state.mcpHealthByServerId[server.id], health.state == .warning {
                return DesignTokens.tierOrange
            }
            return DesignTokens.Colors.statusSuccess
        }
        return DesignTokens.inkTertiary.opacity(0.4)
    }

    private var expandedDetailView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Text(server.transportLabel)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(DesignTokens.storeBlueTint)
                    .clipShape(Capsule())

                Text(server.category)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)

                Spacer(minLength: 0)

                let fp = state.contextUsage.mcpFootprint(for: server.id)
                if fp.claudeStartupTokens > 0 {
                    let toolsSuffix = fp.toolCount > 0 ? "\(fp.toolCount)t · " : ""
                    Text("\(toolsSuffix)~\(ResourceFootprint.formatTokens(fp.claudeStartupTokens)) tok")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .help("Estimated Context Footprint: ~\(fp.antigravityStartupTokens) tok (Antigravity) / ~\(fp.claudeStartupTokens) tok (Claude Code)")
                }
            }

            HStack(alignment: .top, spacing: DesignTokens.Spacing.xxs) {
                Text(server.displayEndpoint)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    let text = server.serverUrl ?? server.summary
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(DesignTokens.snappySpring) { isCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(DesignTokens.snappySpring) { isCopied = false }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5))
                        .foregroundStyle(isCopied ? DesignTokens.Colors.statusSuccess : DesignTokens.inkTertiary)
                }
                .buttonStyle(.plain)
                .help("Copy server endpoint")
                .accessibilityLabel("Copy endpoint for \(server.name)")
            }
            .padding(DesignTokens.Spacing.xxs)
            .background(DesignTokens.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let health = state.mcpHealthByServerId[server.id],
               health.state == .error || health.state == .warning {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: health.state == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(health.state == .error ? DesignTokens.Colors.statusError : DesignTokens.tierOrange)
                    Text("\(health.summary): \(health.detail)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(health.state == .error ? DesignTokens.Colors.statusError : DesignTokens.tierOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                if isInheritedGlobal, let pId = projectId {
                    Button {
                        state.demoteGlobalResourceToProjects(kind: .mcp, id: server.id, projectIds: [pId])
                    } label: {
                        Label("Move to Project-only", systemImage: "arrow.down.right.circle")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Remove \(server.name) from Global Core and keep enabled only in \(project?.name ?? "this project")")
                }

                Button {
                    state.navigationSelection = .masterVault
                    WindowRouter.triggerOpen()
                } label: {
                    Label("Control Center", systemImage: "macwindow")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Open \(server.name) in Control Center Master Vault")
            }
        }
        .padding(.leading, 14)
        .padding(.bottom, DesignTokens.Spacing.xxs)
    }

    private var serverSubtitle: String {
        let base = server.displayEndpoint
        if isInheritedGlobal {
            return "Inherited • \(base)"
        }
        return base
    }

    @ViewBuilder
    private var toggleControl: some View {
        if isInheritedGlobal {
            Toggle("", isOn: Binding(
                get: { true },
                set: { newValue in
                    if !newValue {
                        state.disableGlobalServerFromProject(id: server.id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Disable \(server.name) in Global Core (applies to all workspaces)")
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
