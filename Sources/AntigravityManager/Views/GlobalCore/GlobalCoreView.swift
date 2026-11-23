import SwiftUI

public struct GlobalCoreView: View {
    @Bindable var state: AppState
    @Binding var deletionTarget: DeletionTarget?
    @Binding var editingSkill: SkillDefinition?
    @State private var selectedTab: Int = 0

    public init(
        state: AppState,
        deletionTarget: Binding<DeletionTarget?>,
        editingSkill: Binding<SkillDefinition?>
    ) {
        self.state = state
        self._deletionTarget = deletionTarget
        self._editingSkill = editingSkill
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                topActionBar
                globalStatsBar

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    tabSelector

                    switch selectedTab {
                    case 0:
                        GlobalCoreMCPTab(state: state, deletionTarget: $deletionTarget)
                    case 1:
                        GlobalCoreSkillsTab(state: state, deletionTarget: $deletionTarget, editingSkill: $editingSkill)
                    default:
                        GlobalCorePluginsTab(state: state, deletionTarget: $deletionTarget)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.background)
    }

    private var topActionBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("Global Core Profile")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.ink)

                    Text("ALWAYS ACTIVE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.tierOrange)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.tierOrange.opacity(0.15))
                        .clipShape(Capsule())
                }

                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.tierOrange)
                    Text("Active across all Antigravity & Claude Code sessions:")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkSecondary)
                    Text("~/.gemini/config/")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignTokens.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(DesignTokens.tierOrange)
                }
            }

            Spacer()
        }
    }

    private var globalStatsBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            statBadge(icon: "server.rack", count: "\(state.globalServerIds.count)/\(state.servers.count)", label: "MCP Servers", tint: DesignTokens.primary)
            statBadge(icon: "sparkles", count: "\(state.globalSkillIds.count) Active", label: "Skills", tint: DesignTokens.secondary)
            statBadge(icon: "puzzlepiece.extension", count: "\(state.globalPluginIds.count)/\(state.plugins.count)", label: "Plugins", tint: DesignTokens.tierOrange)
            statBadge(icon: "lock.shield", count: "\(state.servers.count)", label: "Master Vault", tint: DesignTokens.secondary)
            Spacer()
        }
    }

    private func statBadge(icon: String, count: String, label: String, tint: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(count)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.inkSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private var tabSelector: some View {
        Picker("", selection: $selectedTab) {
            Text("MCP Connectors (\(state.globalServerIds.count)/\(state.servers.count))")
                .monospacedDigit()
                .tag(0)
            Text("Skills (\(state.globalSkillIds.count)/\(state.skills.count))")
                .monospacedDigit()
                .tag(1)
            Text("Plugins (\(state.globalPluginIds.count)/\(state.plugins.count))")
                .monospacedDigit()
                .tag(2)
        }
        .pickerStyle(.segmented)
    }
}
