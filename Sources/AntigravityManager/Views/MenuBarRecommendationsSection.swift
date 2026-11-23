import SwiftUI
import AppKit

public struct MenuBarRecommendationsSection: View {
    @Bindable var state: AppState
    let projectId: String
    let recommendations: [ResourceRecommendation]
    let stackLabels: [String]
    @State private var isExpanded: Bool = false
    @State private var inspectedKey: String? = nil

    private let collapsedLimit: Int = 3

    public init(
        state: AppState,
        projectId: String,
        recommendations: [ResourceRecommendation],
        stackLabels: [String] = []
    ) {
        self.state = state
        self.projectId = projectId
        self.recommendations = recommendations
        self.stackLabels = stackLabels
    }

    public var body: some View {
        Group {
            if recommendations.isEmpty {
                allActiveBanner
            } else {
                missingRecommendationsCard
            }
        }
        .onChange(of: projectId) { _, _ in
            isExpanded = false
            inspectedKey = nil
        }
    }

    private var stackBadgeText: String {
        stackLabels.isEmpty ? "Repo Stack" : stackLabels.joined(separator: " · ")
    }

    private var dismissedCount: Int {
        state.dismissedRecommendationCount(for: projectId)
    }

    private var essentialRecommendations: [ResourceRecommendation] {
        recommendations.filter { $0.priority == .high }
    }

    private var hiddenCount: Int {
        max(0, recommendations.count - collapsedLimit)
    }

    private var visibleRecommendations: [ResourceRecommendation] {
        isExpanded ? recommendations : Array(recommendations.prefix(collapsedLimit))
    }

    private var hasAnyProjectSpecificResources: Bool {
        guard let proj = state.projects.first(where: { $0.id == projectId }) else { return false }
        let localSkills = state.projectLocalSkills[projectId] ?? []
        return !proj.enabledMCPServerIds.isEmpty
            || !proj.enabledSkillIds.isEmpty
            || !proj.enabledPluginIds.isEmpty
            || !localSkills.isEmpty
    }

    private var allActiveBanner: some View {
        let isConfigured = hasAnyProjectSpecificResources
        return HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: isConfigured ? "checkmark.seal.fill" : "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isConfigured ? DesignTokens.Colors.statusSuccess : DesignTokens.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text("SUGGESTED FOR REPO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.inkSecondary)

                    Text(stackBadgeText)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(DesignTokens.storeBlueTint)
                        .clipShape(Capsule())
                }

                Text(isConfigured
                     ? "All active Vault recommendations for this stack are enabled"
                     : "No project tools active — select MCP/Skills below")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if dismissedCount > 0 {
                restoreDismissedButton
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(isConfigured ? DesignTokens.Colors.statusSuccess.opacity(0.28) : DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private var missingRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.tierOrange)

                Text("SUGGESTED FOR REPO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)

                if !stackLabels.isEmpty {
                    Text(stackBadgeText)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.tierOrange)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(DesignTokens.tierOrange.opacity(0.14))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                headerActionButton
            }

            if isExpanded && recommendations.count > 5 {
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(visibleRecommendations, id: \.uniqueKey) { rec in
                            recommendationRow(rec)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 224)
            } else {
                VStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(visibleRecommendations, id: \.uniqueKey) { rec in
                        recommendationRow(rec)
                    }
                }
            }

            if hiddenCount > 0 || dismissedCount > 0 {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if hiddenCount > 0 {
                        Button {
                            withAnimation(DesignTokens.snappySpring) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text(isExpanded
                                     ? "Show fewer"
                                     : "Show \(hiddenCount) more (\(recommendations.count) total)")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded
                              ? "Collapse recommendations back to top 3"
                              : "Reveal all \(recommendations.count) recommended tools before enabling")
                    }

                    Spacer(minLength: 0)

                    if dismissedCount > 0 {
                        restoreDismissedButton
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.tierOrange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.tierOrange.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var headerActionButton: some View {
        if !isExpanded && !essentialRecommendations.isEmpty && essentialRecommendations.count < recommendations.count {
            Button {
                state.enableRecommendations(essentialRecommendations, for: projectId)
            } label: {
                Text("Enable Essential (\(essentialRecommendations.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(DesignTokens.storeBlueTint)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Enable \(essentialRecommendations.count) essential stack tools: \(essentialRecommendations.map(\.name).joined(separator: ", "))")
        } else if !isExpanded && hiddenCount > 0 {
            Button {
                withAnimation(DesignTokens.snappySpring) {
                    isExpanded = true
                }
            } label: {
                Text("Show All (\(recommendations.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.tierOrange)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(DesignTokens.tierOrange.opacity(0.14))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Expand to inspect all \(recommendations.count) recommended tools")
        } else if recommendations.count > 1 {
            Button {
                state.enableAllRecommendations(for: projectId)
            } label: {
                Text("Enable All (\(recommendations.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(DesignTokens.storeBlueTint)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Enable all \(recommendations.count) visible tools: \(recommendations.map(\.name).joined(separator: ", "))")
        }
    }

    private var restoreDismissedButton: some View {
        Button {
            state.resetDismissedRecommendations(for: projectId)
        } label: {
            Text("Restore \(dismissedCount) dismissed")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignTokens.inkSecondary)
                .underline()
        }
        .buttonStyle(.plain)
        .help("Restore \(dismissedCount) dismissed suggestion(s) for this project")
    }

    private func recommendationRow(_ rec: ResourceRecommendation) -> some View {
        let isInspected = inspectedKey == rec.uniqueKey
        let kindColor = rec.priority == .low ? DesignTokens.inkSecondary : DesignTokens.tierOrange
        let kindBg = rec.priority == .low ? DesignTokens.surfaceContainer : DesignTokens.tierOrange.opacity(0.14)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Button {
                    toggleInspection(for: rec)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(rec.kind.displayLabel)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(kindColor)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 2)
                            .background(kindBg)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: DesignTokens.Spacing.xxs) {
                                Text(rec.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignTokens.ink)
                                    .lineLimit(1)

                                if rec.priority == .low {
                                    Text("OPT")
                                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(DesignTokens.inkTertiary)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(DesignTokens.surfaceContainer)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }

                                Image(systemName: isInspected ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(DesignTokens.inkTertiary)
                            }

                            Text(rec.reason)
                                .font(.system(size: 9.5))
                                .foregroundStyle(DesignTokens.inkSecondary)
                                .lineLimit(isInspected ? nil : 1)
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isInspected ? "Hide details for \(rec.name)" : "Inspect what \(rec.name) does before enabling")
                .accessibilityLabel("Inspect \(rec.name) suggestion")

                Button {
                    state.dismissRecommendation(rec, for: projectId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .frame(width: 18, height: 18)
                        .background(DesignTokens.surfaceContainerLow)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss \(rec.name) suggestion for this project")
                .accessibilityLabel("Dismiss \(rec.name)")

                Button {
                    state.enableRecommendedResource(rec, for: projectId)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Enable")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.surfaceContainerLowest)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(DesignTokens.secondary.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Enable \(rec.name) (\(rec.kind.displayLabel)) for the active project")
            }

            if isInspected {
                recommendationDetailPanel(for: rec)
            }
        }
        .task(id: "\(rec.uniqueKey)-\(isInspected)") {
            if isInspected, rec.kind == .skill, let skill = resolvedSkill(for: rec) {
                state.loadSkillPreviewIfNeeded(for: skill)
            }
        }
    }

    @ViewBuilder
    private func recommendationDetailPanel(for rec: ResourceRecommendation) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            switch rec.kind {
            case .skill:
                if let skill = resolvedSkill(for: rec) {
                    skillRecommendationDetails(skill)
                } else {
                    Text(rec.reason)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .plugin:
                if let plugin = state.plugins.first(where: { $0.id == rec.id }) {
                    pluginRecommendationDetails(plugin)
                } else {
                    Text(rec.reason)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .mcp:
                if let server = state.servers.first(where: { $0.id == rec.id }) {
                    mcpRecommendationDetails(server)
                } else {
                    Text(rec.reason)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 0.75)
        )
    }

    private func skillRecommendationDetails(_ skill: SkillDefinition) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Text(skill.category)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(DesignTokens.storeBlueTint)
                    .clipShape(Capsule())

                Text(skill.id)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = state.skillPreviews[skill.id], !preview.isEmpty, preview != skill.description {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SKILL.MD EXCERPT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.inkTertiary)

                    Text(preview)
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DesignTokens.Spacing.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if state.skillPreviews[skill.id] == nil {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading SKILL.md preview…")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                Button {
                    state.openSkillInControlCenter(skill)
                } label: {
                    Label("Full SKILL.md", systemImage: "doc.text")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Open \(skill.name) in Control Center Skill Editor")

                Button {
                    NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Finder", systemImage: "folder")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Reveal \(skill.id) folder in Finder")

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func pluginRecommendationDetails(_ plugin: PluginDefinition) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                if plugin.hasMCP {
                    Text("Includes MCP")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(DesignTokens.storeBlueTint)
                        .clipShape(Capsule())
                }
                if plugin.hasSkills {
                    Text("Bundled Skills")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.tierOrange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(DesignTokens.tierOrange.opacity(0.14))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }

            Text(plugin.description.isEmpty ? "Plugin package inside Master Vault." : plugin.description)
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    private func mcpRecommendationDetails(_ server: MCPServerDefinition) -> some View {
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
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)

                Spacer(minLength: 0)
            }

            Text(server.displayEndpoint)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(DesignTokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let health = state.mcpHealthByServerId[server.id],
               health.state == .warning || health.state == .error {
                Text("\(health.summary): \(health.detail)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(health.state == .error ? DesignTokens.Colors.statusError : DesignTokens.tierOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resolvedSkill(for rec: ResourceRecommendation) -> SkillDefinition? {
        state.skills.first(where: { $0.id == rec.id })
            ?? (state.projectLocalSkills[projectId] ?? []).first(where: { $0.id == rec.id })
    }

    private func toggleInspection(for rec: ResourceRecommendation) {
        withAnimation(DesignTokens.snappySpring) {
            inspectedKey = (inspectedKey == rec.uniqueKey) ? nil : rec.uniqueKey
        }
        if rec.kind == .skill, let skill = resolvedSkill(for: rec) {
            state.loadSkillPreviewIfNeeded(for: skill)
        }
    }
}
