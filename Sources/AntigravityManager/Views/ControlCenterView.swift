import SwiftUI

public struct ControlCenterView: View {
    @Bindable var state: AppState
    @State private var deletionTarget: DeletionTarget? = nil
    @State private var editingSkill: SkillDefinition? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        Group {
            if !state.isProjectsFolderAuthorized {
                ProjectFolderOnboardingView(state: state)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    ControlCenterSidebar(state: state, selection: selectionBinding)
                } detail: {
                    VStack(spacing: 0) {
                        detailContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ControlCenterFooter(state: state)
                    }
                    .background(DesignTokens.background)
                    .navigationTitle(navigationTitle)
                    .toolbar { syncToolbarItem }
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(
            minWidth: DesignTokens.Dimensions.windowMinWidth,
            minHeight: DesignTokens.Dimensions.windowMinHeight
        )
        .sheet(item: $editingSkill) { skill in
            SkillEditorSheet(skill: skill) { _ in state.reloadSkills() }
        }
        .alert(item: $deletionTarget) { target in
            deletionAlert(for: target)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch state.navigationSelection {
        case .masterVault:
            MasterVaultView(state: state, deletionTarget: $deletionTarget, editingSkill: $editingSkill)
        case .globalCore:
            GlobalCoreView(state: state, deletionTarget: $deletionTarget, editingSkill: $editingSkill)
        case .plugins:
            PluginsView(state: state, deletionTarget: $deletionTarget)
        case .project(let projectId):
            if let project = state.projects.first(where: { $0.id == projectId }) {
                ProjectDetailView(state: state, project: project, deletionTarget: $deletionTarget, editingSkill: $editingSkill)
            } else {
                EmptyStateView.noProjectSelected
            }
        case .systemBuiltins:
            SystemBuiltinsView(state: state, editingSkill: $editingSkill)
        case .skillEditor:
            if let first = state.skills.first ?? state.builtinSkills.first {
                SkillEditorSheet(skill: first) { _ in state.reloadSkills() }
            } else {
                Text("No skills available to edit.").foregroundStyle(DesignTokens.inkTertiary)
            }
        case .syncLogs:
            SyncLogsView(state: state)
        case .settings:
            SettingsView(state: state)
        }
    }

    private var navigationTitle: String {
        switch state.navigationSelection {
        case .masterVault: return "Master Vault"
        case .globalCore: return "Global Core"
        case .plugins: return "Plugins Catalog"
        case .project(let id): return state.projects.first(where: { $0.id == id })?.name ?? "Project"
        case .systemBuiltins: return "System Built-ins"
        case .skillEditor: return "Skill Editor"
        case .syncLogs: return "Sync Engine Logs"
        case .settings: return "Settings"
        }
    }

    private var selectionBinding: Binding<NavigationSection?> {
        Binding(
            get: { state.navigationSelection },
            set: { if let val = $0 { state.navigationSelection = val } }
        )
    }

    @ToolbarContentBuilder
    private var syncToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .status) {
            if state.isSyncing {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Synchronizing...").font(.caption).foregroundStyle(DesignTokens.inkSecondary)
                }
            } else if let lastSync = state.lastSyncDate {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Circle().fill(DesignTokens.secondary).frame(width: 6, height: 6)
                    Text("Synced (\(lastSync.formatted(date: .omitted, time: .standard)))")
                        .font(.caption).foregroundStyle(DesignTokens.inkSecondary)
                }
            } else {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Circle().fill(DesignTokens.secondary).frame(width: 6, height: 6)
                    Text("Master Vault Ready")
                        .font(.caption).foregroundStyle(DesignTokens.inkSecondary)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PathConstants.vaultDirectory.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal Master Vault folder in Finder (⇧⌘R)")

            Button {
                Task { await state.refreshProjects() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh workspaces from disk (⌘R)")

            Button {
                state.syncAll()
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if state.isSyncing {
                        ProgressView().controlSize(.small)
                        Text("Syncing...")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync All")
                    }
                }
            }
            .disabled(state.isSyncing)
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primaryContainer)
            .help("Synchronize all workspaces and Vault to disk (⌘S)")
        }
    }

    private func deletionAlert(for target: DeletionTarget) -> Alert {
        Alert(
            title: Text("Uninstall \(target.typeTitle)?"),
            message: Text("Are you sure you want to permanently delete \"\(target.name)\" from your Mac? This removes all associated files, configurations, and project assignments."),
            primaryButton: .destructive(Text("Uninstall Permanently")) {
                Task {
                    switch target {
                    case .server(let s): await state.deleteServer(id: s.id)
                    case .skill(let s): await state.deleteSkill(id: s.id)
                    case .plugin(let p): await state.deletePlugin(id: p.id)
                    }
                }
            },
            secondaryButton: .cancel()
        )
    }
}
