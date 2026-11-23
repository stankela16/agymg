import SwiftUI
import AppKit

public struct ControlCenterView: View {
    @Bindable var state: AppState
    @State private var deletionTarget: DeletionTarget? = nil
    @State private var editingSkill: SkillDefinition? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented: Bool = false

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
                    .inspector(isPresented: $isInspectorPresented) {
                        inspectorContent
                            .inspectorColumnWidth(min: 250, ideal: 280, max: 320)
                    }
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
        .onAppear {
            consumeRequestedSkillToEdit()
        }
        .onChange(of: state.requestedSkillToEdit) { _, _ in
            consumeRequestedSkillToEdit()
        }
    }

    private func consumeRequestedSkillToEdit() {
        if let requested = state.requestedSkillToEdit {
            editingSkill = requested
            state.requestedSkillToEdit = nil
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

    @ViewBuilder
    private var inspectorContent: some View {
        ScrollView {
            Group {
                switch state.navigationSelection {
                case .globalCore:
                    GlobalCoreInspectorView(state: state)
                case .project(let projectId):
                    if let project = state.projects.first(where: { $0.id == projectId }) {
                        ProjectIsolationSidebarView(
                            project: project,
                            state: state,
                            onLinkSkillTap: { state.requestedProjectTab = 1 }
                        )
                    } else {
                        MasterVaultInspectorView(state: state)
                    }
                default:
                    MasterVaultInspectorView(state: state)
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(DesignTokens.panel)
    }

    private var diagnosticsStatus: (hasAttention: Bool, hasErrors: Bool) {
        let activeServerIds = state.globalServerIds.union(state.projects.flatMap(\.enabledMCPServerIds))
        let activeHealth = state.mcpHealthByServerId.filter { activeServerIds.contains($0.key) }.values
        let auditFailed = state.projectSafetyAudits.values.contains { $0.overallStatus == .failed }
        let hasErrors = auditFailed
            || activeHealth.contains { $0.state == .error }
            || state.driftIssues.contains { $0.severity == .error }
        let auditWarn = state.projects.contains { proj in
            !proj.enabledMCPServerIds.isEmpty && state.projectSafetyAudits[proj.id]?.overallStatus == .warning
        }
        let hasWarnings = auditWarn
            || activeHealth.contains { $0.state == .warning }
            || state.driftIssues.contains { $0.severity == .warning }
        return (hasErrors || hasWarnings, hasErrors)
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
                Label("Vault Folder", systemImage: "folder")
            }
            .help("Reveal Master Vault folder in Finder (⇧⌘R)")

            Button {
                Task { await state.refreshProjects() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh workspaces from disk (⌘R)")

            let diag = diagnosticsStatus
            Button {
                withAnimation(DesignTokens.snappySpring) {
                    isInspectorPresented.toggle()
                }
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
                    .overlay(alignment: .topTrailing) {
                        if diag.hasAttention && !isInspectorPresented {
                            Circle()
                                .fill(diag.hasErrors ? DesignTokens.Colors.statusError : DesignTokens.tierOrange)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(isInspectorPresented ? "Hide Inspector panel (⌥⌘I)" : "Show Inspector panel (⌥⌘I)")

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
