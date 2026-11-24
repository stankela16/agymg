import SwiftUI

public struct ContextHealthBadge: View {
    let summary: WorkspaceContextSummary
    var compact: Bool = true

    public init(summary: WorkspaceContextSummary, compact: Bool = true) {
        self.summary = summary
        self.compact = compact
    }

    private var accentColor: Color {
        switch summary.health {
        case .clean: return DesignTokens.Colors.statusSuccess
        case .heavy: return DesignTokens.tierOrange
        case .bloated: return DesignTokens.Colors.statusError
        }
    }

    private var backgroundColor: Color {
        switch summary.health {
        case .clean: return DesignTokens.Colors.statusSuccessBg
        case .heavy: return DesignTokens.Colors.statusWarningBg
        case .bloated: return DesignTokens.Colors.statusErrorBg
        }
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Circle()
                .fill(accentColor)
                .frame(width: 5.5, height: 5.5)

            if compact {
                Text(summary.health.badgeLabel)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
            } else {
                Text(summary.totalDormantCount > 0
                     ? "\(summary.health.badgeLabel) · \(summary.totalDormantCount) dormant"
                     : summary.health.badgeLabel)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor)
        .clipShape(Capsule())
        .help(
            "Context Health: \(summary.health.badgeLabel) · \(summary.totalDormantCount) dormant in 30d · Always-on: ~\(summary.formattedAntigravityTokens) tok (Antigravity) / ~\(summary.formattedClaudeTokens) tok (Claude Code)"
        )
    }
}

public struct WorkspaceContextAuditCard: View {
    @Bindable var state: AppState
    let project: ProjectProfile?

    public init(state: AppState, project: ProjectProfile?) {
        self.state = state
        self.project = project
    }

    private struct AuditItem: Identifiable {
        let id: String
        let resourceId: String
        let name: String
        let kind: ManagedResourceKind
        let isGlobal: Bool
        let callsHere: Int
        let totalCalls: Int
        let usedProjectCount: Int
        let footprint: ResourceFootprint
    }

    private var summary: WorkspaceContextSummary {
        state.contextSummary(for: project)
    }

    private var dormantItems: [AuditItem] {
        var items: [AuditItem] = []

        for mcpId in summary.dormantGlobalMCPIds + summary.dormantProjectMCPIds {
            let isGlobal = state.globalServerIds.contains(mcpId)
            let name = state.servers.first(where: { $0.id == mcpId })?.name ?? mcpId
            let stats = state.contextUsage.mcpStats(for: mcpId)
            let fp = state.contextUsage.mcpFootprint(for: mcpId)
            items.append(AuditItem(
                id: "mcp:\(mcpId)",
                resourceId: mcpId,
                name: name,
                kind: .mcp,
                isGlobal: isGlobal,
                callsHere: project.map { stats.calls(inProject: $0.id) } ?? stats.totalCalls30d,
                totalCalls: stats.totalCalls30d,
                usedProjectCount: stats.usedProjectIds.count,
                footprint: fp
            ))
        }

        for skillId in summary.dormantGlobalSkillIds + summary.dormantProjectSkillIds {
            let isGlobal = state.globalSkillIds.contains(skillId)
            let name = state.skills.first(where: { $0.id == skillId })?.name ?? skillId
            let stats = state.contextUsage.skillStats(for: skillId)
            let fp = state.contextUsage.skillFootprint(for: skillId)
            items.append(AuditItem(
                id: "skill:\(skillId)",
                resourceId: skillId,
                name: name,
                kind: .skill,
                isGlobal: isGlobal,
                callsHere: project.map { stats.calls(inProject: $0.id) } ?? stats.totalCalls30d,
                totalCalls: stats.totalCalls30d,
                usedProjectCount: stats.usedProjectIds.count,
                footprint: fp
            ))
        }

        return items.sorted { lhs, rhs in
            if lhs.footprint.claudeStartupTokens != rhs.footprint.claudeStartupTokens {
                return lhs.footprint.claudeStartupTokens > rhs.footprint.claudeStartupTokens
            }
            return lhs.name < rhs.name
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            headerRow
            metricsRow

            if !dormantItems.isEmpty {
                Divider().background(DesignTokens.hairline)
                dormantListSection
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.secondary)

            Text("Context & Usage (30d)")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DesignTokens.ink)

            ContextHealthBadge(summary: summary, compact: false)

            Spacer(minLength: 0)

            if let project, summary.dormantProjectTotalCount > 0 {
                Button {
                    state.disableDormantProjectResources(projectId: project.id)
                } label: {
                    Label("Disable Dormant (\(summary.dormantProjectTotalCount))", systemImage: "wand.and.stars")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("Disable all Project Scope resources with 0 invocations in \(project.name) over the last 30 days")
            }

            Button {
                Task { @MainActor in
                    await state.refreshContextUsage()
                }
            } label: {
                if state.isRefreshingContextUsage {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DesignTokens.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isRefreshingContextUsage)
            .help("Refresh 30-day usage analytics from local transcripts (\(state.contextUsage.scannedSessionsCount) sessions)")
        }
    }

    private var metricsRow: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            metricTile(
                label: "ANTIGRAVITY",
                value: "~\(summary.formattedAntigravityTokens) tok",
                caption: "Always-on startup"
            )
            metricTile(
                label: "CLAUDE CODE",
                value: "~\(summary.formattedClaudeTokens) tok",
                caption: "Eager MCP + skills"
            )
            metricTile(
                label: "DORMANT (30D)",
                value: "\(summary.totalDormantCount)",
                caption: "Of \(summary.activeMCPCount + summary.activeSkillCount) active",
                highlight: summary.totalDormantCount >= 3
            )
        }
    }

    private func metricTile(label: String, value: String, caption: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.inkTertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(highlight ? DesignTokens.tierOrange : DesignTokens.ink)
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(DesignTokens.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var dormantListSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text("TOP DORMANT RESOURCES (0 CALLS IN 30 DAYS)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.inkTertiary)

            ForEach(dormantItems.prefix(6)) { item in
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: item.kind == .mcp ? "server.rack" : "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Text(item.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignTokens.ink)
                                .lineLimit(1)

                            Text(item.isGlobal ? "GLOBAL" : "PROJECT")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(item.isGlobal ? DesignTokens.tierOrange : DesignTokens.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background((item.isGlobal ? DesignTokens.tierOrange : DesignTokens.secondary).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Text(itemSubtitle(item))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    actionButton(for: item)
                }
                .padding(.vertical, 3)
            }

            if dormantItems.count > 6 {
                Text("+\(dormantItems.count - 6) more dormant resources")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func itemSubtitle(_ item: AuditItem) -> String {
        let tokPart: String
        if item.kind == .mcp {
            let toolsPart = item.footprint.toolCount > 0 ? "\(item.footprint.toolCount) tools · " : ""
            tokPart = "\(toolsPart)~\(ResourceFootprint.formatTokens(item.footprint.claudeStartupTokens)) tok"
        } else {
            tokPart = "~\(ResourceFootprint.formatTokens(item.footprint.antigravityStartupTokens)) tok startup"
        }

        if project != nil && item.totalCalls > 0 {
            return "0x here · \(item.totalCalls)x in \(item.usedProjectCount) other proj · \(tokPart)"
        }
        return "0x in 30d · \(tokPart)"
    }

    @ViewBuilder
    private func actionButton(for item: AuditItem) -> some View {
        if item.isGlobal && item.usedProjectCount > 0 {
            Button("Used Projects Only") {
                state.moveGlobalResourceToUsedProjects(kind: item.kind, id: item.resourceId)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Remove \(item.name) from Global Core and enable it only in the \(item.usedProjectCount) project(s) where it was used")
        } else {
            Button("Disable") {
                if item.isGlobal {
                    switch item.kind {
                    case .mcp: state.disableGlobalServerFromProject(id: item.resourceId)
                    case .skill: state.disableGlobalSkillFromProject(id: item.resourceId)
                    case .plugin: state.disableGlobalPluginFromProject(id: item.resourceId)
                    }
                } else if let project {
                    switch item.kind {
                    case .mcp: state.toggleProjectServer(projectId: project.id, serverId: item.resourceId)
                    case .skill: state.toggleProjectSkill(projectId: project.id, skillId: item.resourceId)
                    case .plugin: state.toggleProjectPlugin(projectId: project.id, pluginId: item.resourceId)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Disable \(item.name)")
        }
    }
}
