import SwiftUI

public struct MasterVaultView: View {
    @Bindable var state: AppState
    @Binding var deletionTarget: DeletionTarget?
    @Binding var editingSkill: SkillDefinition?
    @State private var vaultTab: Int = 0
    @State private var showingAddServer: Bool = false
    @State private var showingNewSkill: Bool = false

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
                resourceStatsBar
                VaultGuidanceBannerView(state: state)

                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    // Left Column (65-70%)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        tabSelector

                        switch vaultTab {
                        case 0:
                            VaultServersTab(state: state, deletionTarget: $deletionTarget)
                        case 1:
                            VaultSkillsTab(state: state, deletionTarget: $deletionTarget, editingSkill: $editingSkill)
                        default:
                            VaultPluginsTab(state: state, deletionTarget: $deletionTarget)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right Column: Inspector Cards
                    MasterVaultInspectorView(state: state)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.background)
        .sheet(isPresented: $showingAddServer) {
            EditMCPServerSheet(state: state)
        }
        .sheet(isPresented: $showingNewSkill) {
            NewSkillSheet(state: state) { created in
                editingSkill = created
            }
        }
    }

    private var topActionBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("Master Vault")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.ink)

                    Text("ACTIVE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.secondaryContainer.opacity(0.35))
                        .clipShape(Capsule())
                }

                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Central single source of truth:")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkSecondary)
                    Text("~/.gemini/manager-vault/")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignTokens.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(DesignTokens.primary)
                }
            }

            Spacer()

            HStack(spacing: DesignTokens.Spacing.xs) {
                if vaultTab == 0 {
                    Button {
                        showingAddServer = true
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Image(systemName: "plus")
                            Text("Add Server")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .help("Add a new MCP server to Master Vault")
                } else if vaultTab == 1 {
                    Button {
                        showingNewSkill = true
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Image(systemName: "plus")
                            Text("New Skill")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .help("Create a new skill in Master Vault")
                }

                Button {
                    state.syncAll()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "bolt.fill")
                        Text("Sync All Projects")
                    }
                    .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.primaryContainer)
                .help("Synchronize all global and project resources (⌘S)")
            }
        }
    }

    private var resourceStatsBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            statBadge(icon: "server.rack", count: "\(state.servers.count)", label: "MCP Servers")
            statBadge(icon: "sparkles", count: "\(state.skills.count)", label: "Skills")
            statBadge(icon: "folder.fill", count: "\(state.projects.count)", label: "Projects")
            statBadge(icon: "globe", count: "\(state.globalServerIds.count)", label: "Global Active")
            Spacer()
        }
    }

    private func statBadge(icon: String, count: String, label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.secondary)
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
        HStack(spacing: DesignTokens.Spacing.sm) {
            Picker("", selection: $vaultTab) {
                Text("MCP Servers (\(state.servers.count))").tag(0)
                Text("Skills (\(state.skills.count))").tag(1)
                Text("Plugins (\(state.plugins.count))").tag(2)
            }
            .pickerStyle(.segmented)
            .monospacedDigit()

            Spacer()
        }
    }
}
