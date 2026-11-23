import SwiftUI
import AppKit

public struct ProjectDetailView: View {
    @Bindable var state: AppState
    let projectId: String
    private let initialProject: ProjectProfile
    @Binding var deletionTarget: DeletionTarget?
    @Binding var editingSkill: SkillDefinition?
    @State private var selectedTab: Int = 0

    public init(
        state: AppState,
        project: ProjectProfile,
        deletionTarget: Binding<DeletionTarget?>,
        editingSkill: Binding<SkillDefinition?>
    ) {
        self.state = state
        self.projectId = project.id
        self.initialProject = project
        self._deletionTarget = deletionTarget
        self._editingSkill = editingSkill
    }

    private var project: ProjectProfile {
        state.projects.first(where: { $0.id == projectId }) ?? initialProject
    }

    private var displayPath: String {
        let raw = project.path
        let effHome = PathConstants.effectiveHomeDirectory.path
        if raw == effHome { return "~" }
        if raw.hasPrefix(effHome + "/") {
            return "~" + String(raw.dropFirst(effHome.count))
        }
        let sysHome = PathConstants.homeDirectory.path
        if raw == sysHome { return "~" }
        if raw.hasPrefix(sysHome + "/") {
            return "~" + String(raw.dropFirst(sysHome.count))
        }
        return raw
    }

    private var totalSkillsCount: Int {
        let localIds = Set(state.localSkills(for: project).map(\.id))
        return localIds.union(project.enabledSkillIds).count
    }

    private var stackLabels: [String] {
        state.projectStackLabels[project.id] ?? []
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                topBreadcrumb
                headerSection
                projectStatsBar
                ProjectIsolationBannerView(projectName: project.name)
                ProjectRecommendationsCard(state: state, projectId: project.id)

                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    // Left Column
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        tabSelector

                        switch selectedTab {
                        case 0:
                            ProjectServersTab(state: state, projectId: project.id, deletionTarget: $deletionTarget)
                        case 1:
                            ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: $deletionTarget, editingSkill: $editingSkill)
                        default:
                            ProjectPluginsTab(state: state, projectId: project.id, deletionTarget: $deletionTarget)
                        }

                        RuntimeManifestPreviewView(project: project, state: state)
                            .padding(.top, DesignTokens.Spacing.xxs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right Column
                    ProjectIsolationSidebarView(
                        project: project,
                        state: state,
                        onLinkSkillTap: { selectedTab = 1 }
                    )
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.background)
    }

    private var topBreadcrumb: some View {
        HStack(spacing: 6) {
            Text("Projects").font(.system(size: 11)).foregroundStyle(DesignTokens.inkSecondary)
            Text("/").font(.system(size: 10)).foregroundStyle(DesignTokens.inkTertiary)
            Text(project.name).font(.system(size: 11, weight: .bold)).foregroundStyle(DesignTokens.ink)

            if state.selectedProjectId == project.id {
                Text("Active Workspace")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(DesignTokens.secondaryContainer.opacity(0.3))
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private var copySourceProjects: [ProjectProfile] {
        state.projects.filter {
            $0.id != project.id && (
                !$0.enabledMCPServerIds.isEmpty
                || !$0.enabledSkillIds.isEmpty
                || !$0.enabledPluginIds.isEmpty
            )
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(project.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.ink)

                    Text("PROJECT")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(DesignTokens.secondaryContainer.opacity(0.35))
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(displayPath)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(DesignTokens.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    ForEach(stackLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(DesignTokens.storeBlueTint)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            HStack(spacing: DesignTokens.Spacing.xs) {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Finder")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal project folder in Finder")

                Button {
                    state.openTerminal(for: project.path)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                        Text("Terminal")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Terminal in this folder")

                if !copySourceProjects.isEmpty {
                    Menu {
                        Section("Merge Tools From Project") {
                            ForEach(copySourceProjects) { source in
                                Button {
                                    state.copySetup(from: source.id, to: project.id, mode: .merge)
                                } label: {
                                    Text("\(source.name) (\(source.enabledMCPServerIds.count) MCP · \(source.enabledSkillIds.count) Skills · \(source.enabledPluginIds.count) Plugins)")
                                }
                            }
                        }
                        Menu("Replace Setup Instead") {
                            ForEach(copySourceProjects) { source in
                                Button(role: .destructive) {
                                    state.copySetup(from: source.id, to: project.id, mode: .replace)
                                } label: {
                                    Text("Replace with \(source.name)")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Setup")
                        }
                        .font(.system(size: 11))
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .help("Copy MCP servers, skills, and plugins from another configured project")
                }

                Button {
                    state.triggerProjectSync(project: project)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("Sync Project")
                    }
                    .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.primaryContainer)
                .controlSize(.small)
                .help("Synchronize resources for this project (⌘S)")
            }
        }
    }

    private var projectStatsBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            statBadge(icon: "server.rack", count: "\(project.enabledMCPServerIds.count)", label: "Scoped MCPs")
            statBadge(icon: "sparkles", count: "\(totalSkillsCount)", label: "Skills")
            statBadge(icon: "puzzlepiece.extension", count: "\(project.enabledPluginIds.count)", label: "Plugins")
            Spacer()
        }
    }

    private func statBadge(icon: String, count: String, label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(DesignTokens.secondary)
            Text(count).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(DesignTokens.ink)
            Text(label).font(.system(size: 11)).foregroundStyle(DesignTokens.inkSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var tabSelector: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                Text("Scoped MCP Servers (\(project.enabledMCPServerIds.count))").tag(0)
                Text("Linked Skills (\(totalSkillsCount))").tag(1)
                Text("Plugins (\(project.enabledPluginIds.count))").tag(2)
            }
            .pickerStyle(.segmented)
            .monospacedDigit()
            Spacer()
        }
    }
}
