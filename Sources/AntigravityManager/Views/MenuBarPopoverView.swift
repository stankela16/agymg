import SwiftUI
import AppKit

public enum MenuBarResourceTab: String, CaseIterable, Sendable {
    case mcp = "MCP"
    case skills = "Skills"
    case plugins = "Plugins"
}

public struct MenuBarPopoverView: View {
    @Bindable var state: AppState
    @State private var selectedTab: MenuBarResourceTab = .mcp
    @State private var isHoveredOpen: Bool = false
    @State private var isHoveredSettings: Bool = false
    @State private var isHoveredQuit: Bool = false

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            headerSection
            Divider().background(DesignTokens.hairline)
            activeContextSection

            if let selectedProject = state.selectedProject {
                let recs = state.projectRecommendations[selectedProject.id] ?? []
                let stackLabels = state.projectStackLabels[selectedProject.id] ?? []
                MenuBarRecommendationsSection(
                    state: state,
                    projectId: selectedProject.id,
                    recommendations: recs,
                    stackLabels: stackLabels
                )
            }

            Divider().background(DesignTokens.hairline)
            resourcesTabSection
            Divider().background(DesignTokens.hairline)
            actionButtonsSection
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(width: DesignTokens.Dimensions.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Material.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
        .onAppear {
            guard !PathConstants.isRunningUnderTests, state.autoFollowWorkspace else { return }
            Task { @MainActor in
                await state.workspaceMonitor.checkIDefocusWorkspace()
            }
        }
        .onExitCommand {
            WindowRouter.dismissPopover()
        }
    }

    private var headerSection: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .shadow(color: Color.green.opacity(0.6), radius: 3)

            Text("agymg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ink)

            Spacer()

            Button {
                state.autoFollowWorkspace.toggle()
                if state.autoFollowWorkspace {
                    Task { @MainActor in
                        await state.workspaceMonitor.checkIDefocusWorkspace()
                    }
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: state.autoFollowWorkspace ? "bolt.horizontal.fill" : "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(state.autoFollowWorkspace ? "AUTO" : "LOCKED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(state.autoFollowWorkspace ? DesignTokens.secondary : DesignTokens.inkSecondary)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, 2)
                .background(state.autoFollowWorkspace ? DesignTokens.storeBlueTint : DesignTokens.surfaceContainer)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(state.autoFollowWorkspace
                ? "Auto-Follow enabled: automatically tracks the active project in Antigravity / Claude / IDE (click to lock)"
                : "Auto-Follow locked to current selection (click to automatically follow active project)")

            Text("⌃⌥A")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.inkSecondary)
                .padding(.horizontal, DesignTokens.Spacing.xxs)
                .padding(.vertical, 2)
                .background(DesignTokens.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
                .help("Global shortcut for Control Center (⌃⌥A)")
        }
        .padding(.horizontal, DesignTokens.Spacing.xxs)
    }

    private var activeContextSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack {
                Text("ACTIVE CONTEXT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
                Spacer()
                if let selected = state.selectedProject {
                    Text(projectSummaryText(for: selected))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, 2)
                        .background(DesignTokens.storeBlueTint)
                        .clipShape(Capsule())
                } else {
                    Text("\(state.globalServerIds.count) MCP · \(state.globalSkillIds.count) Skills · \(state.globalPluginIds.count) Plugins")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.tierOrange)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, 2)
                        .background(DesignTokens.tierOrange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Picker("", selection: Binding(
                get: { state.selectedProjectId ?? "" },
                set: { newId in
                    if newId.isEmpty {
                        state.selectedProjectId = nil
                        state.navigationSelection = .globalCore
                    } else {
                        state.selectedProjectId = newId
                        state.navigationSelection = .project(newId)
                    }
                }
            )) {
                Text("Global Core (All Workspaces)").tag("")
                ForEach(state.projects) { proj in
                    Text(proj.name).tag(proj.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .help("Select active project for quick inspection")
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
    }

    private func projectSummaryText(for project: ProjectProfile) -> String {
        let mcpCount = state.globalServerIds.union(project.enabledMCPServerIds).count
        let localSkills = state.projectLocalSkills[project.id] ?? []
        let skillCount = state.globalSkillIds
            .union(project.enabledSkillIds)
            .union(localSkills.map(\.id))
            .count
        let pluginCount = state.globalPluginIds.union(project.enabledPluginIds).count
        return "\(mcpCount) MCP · \(skillCount) Skills · \(pluginCount) Plugins"
    }

    private var resourcesTabSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Picker("Resources", selection: $selectedTab) {
                ForEach(MenuBarResourceTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .help("Switch between MCP servers, skills, and plugins")

            HStack {
                Text(sectionHeaderTitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(1)
                Spacer()
                Text(activeRatioText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxs)

            switch selectedTab {
            case .mcp:
                serversListContent
            case .skills:
                skillsListContent
            case .plugins:
                pluginsListContent
            }
        }
    }

    private func listScrollHeight(itemCount: Int) -> CGFloat {
        let rowHeight: CGFloat = 30
        let calculated = CGFloat(max(itemCount, 1)) * rowHeight
        return min(max(calculated, 88), 224)
    }

    @ViewBuilder
    private var serversListContent: some View {
        let items = sortedServers
        if items.isEmpty {
            Text("No MCP servers registered")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.inkTertiary)
                .padding(.vertical, DesignTokens.Spacing.xxs)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(items) { server in
                        MenuBarServerRow(
                            state: state,
                            server: server,
                            projectId: state.selectedProjectId
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: listScrollHeight(itemCount: items.count))
        }
    }

    @ViewBuilder
    private var skillsListContent: some View {
        let localSkills = currentProjectLocalOnlySkills
        let vaultSkills = sortedSkills
        let totalCount = localSkills.count + vaultSkills.count
        if totalCount == 0 {
            Text("No skills registered in Vault")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.inkTertiary)
                .padding(.vertical, DesignTokens.Spacing.xxs)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(localSkills) { localSkill in
                        MenuBarSkillRow(
                            state: state,
                            skill: localSkill,
                            projectId: state.selectedProjectId,
                            isLocalProjectSkill: true
                        )
                    }
                    ForEach(vaultSkills) { skill in
                        MenuBarSkillRow(
                            state: state,
                            skill: skill,
                            projectId: state.selectedProjectId,
                            isLocalProjectSkill: false
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: listScrollHeight(itemCount: totalCount))
        }
    }

    @ViewBuilder
    private var pluginsListContent: some View {
        let items = sortedPlugins
        if items.isEmpty {
            Text("No plugins registered in Vault")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.inkTertiary)
                .padding(.vertical, DesignTokens.Spacing.xxs)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(items) { plugin in
                        MenuBarPluginRow(
                            state: state,
                            plugin: plugin,
                            projectId: state.selectedProjectId
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: listScrollHeight(itemCount: items.count))
        }
    }

    private var sortedServers: [MCPServerDefinition] {
        let projEnabled = state.selectedProject?.enabledMCPServerIds ?? []
        let globalEnabled = state.globalServerIds
        return state.servers.sorted { lhs, rhs in
            let lActive = projEnabled.contains(lhs.id) || globalEnabled.contains(lhs.id)
            let rActive = projEnabled.contains(rhs.id) || globalEnabled.contains(rhs.id)
            if lActive != rActive { return lActive && !rActive }
            let lProj = projEnabled.contains(lhs.id)
            let rProj = projEnabled.contains(rhs.id)
            if lProj != rProj { return lProj && !rProj }
            return lhs.id < rhs.id
        }
    }

    private var currentProjectLocalOnlySkills: [SkillDefinition] {
        guard let project = state.selectedProject else { return [] }
        let locals = state.projectLocalSkills[project.id] ?? []
        let vaultSkillIds = Set(state.skills.map(\.id))
        return locals.filter { !vaultSkillIds.contains($0.id) }
    }

    private var sortedSkills: [SkillDefinition] {
        let projEnabled = state.selectedProject?.enabledSkillIds ?? []
        let globalEnabled = state.globalSkillIds
        return state.skills.sorted { lhs, rhs in
            let lActive = projEnabled.contains(lhs.id) || globalEnabled.contains(lhs.id)
            let rActive = projEnabled.contains(rhs.id) || globalEnabled.contains(rhs.id)
            if lActive != rActive { return lActive && !rActive }
            let lProj = projEnabled.contains(lhs.id)
            let rProj = projEnabled.contains(rhs.id)
            if lProj != rProj { return lProj && !rProj }
            return lhs.id < rhs.id
        }
    }

    private var sortedPlugins: [PluginDefinition] {
        let projEnabled = state.selectedProject?.enabledPluginIds ?? []
        let globalEnabled = state.globalPluginIds
        return state.plugins.sorted { lhs, rhs in
            let lActive = projEnabled.contains(lhs.id) || globalEnabled.contains(lhs.id)
            let rActive = projEnabled.contains(rhs.id) || globalEnabled.contains(rhs.id)
            if lActive != rActive { return lActive && !rActive }
            let lProj = projEnabled.contains(lhs.id)
            let rProj = projEnabled.contains(rhs.id)
            if lProj != rProj { return lProj && !rProj }
            return lhs.id < rhs.id
        }
    }

    private var sectionHeaderTitle: String {
        let prefix = state.selectedProject?.name.uppercased() ?? "GLOBAL"
        switch selectedTab {
        case .mcp: return "\(prefix) MCP SERVERS"
        case .skills: return "\(prefix) SKILLS"
        case .plugins: return "\(prefix) PLUGINS"
        }
    }

    private var activeRatioText: String {
        switch selectedTab {
        case .mcp:
            if let project = state.selectedProject {
                let activeCount = state.servers.filter {
                    state.globalServerIds.contains($0.id) || project.enabledMCPServerIds.contains($0.id)
                }.count
                return "\(activeCount)/\(state.servers.count) Active"
            } else {
                return "\(state.globalServerIds.count)/\(state.servers.count) Active"
            }
        case .skills:
            if let project = state.selectedProject {
                let localOnlyCount = currentProjectLocalOnlySkills.count
                let activeVaultCount = state.skills.filter {
                    state.globalSkillIds.contains($0.id) || project.enabledSkillIds.contains($0.id)
                }.count
                return "\(activeVaultCount + localOnlyCount)/\(state.skills.count + localOnlyCount) Active"
            } else {
                return "\(state.globalSkillIds.count)/\(state.skills.count) Active"
            }
        case .plugins:
            if let project = state.selectedProject {
                let activeCount = state.plugins.filter {
                    state.globalPluginIds.contains($0.id) || project.enabledPluginIds.contains($0.id)
                }.count
                return "\(activeCount)/\(state.plugins.count) Active"
            } else {
                return "\(state.globalPluginIds.count)/\(state.plugins.count) Active"
            }
        }
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 2) {
            Button {
                WindowRouter.triggerOpen()
            } label: {
                actionRow(title: "Open Control Center", icon: "macwindow", shortcut: "⌘0", isHovered: isHoveredOpen)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("0", modifiers: [.command])
            .onHover { isHoveredOpen = $0 }
            .help("Open Control Center window (⌘0)")

            SettingsLink {
                actionRow(title: "Settings…", icon: "gearshape", shortcut: "⌘,", isHovered: isHoveredSettings, iconColor: DesignTokens.inkSecondary)
            }
            .simultaneousGesture(TapGesture().onEnded {
                WindowRouter.dismissPopover()
            })
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: [.command])
            .onHover { isHoveredSettings = $0 }
            .help("Open application settings (⌘,)")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                actionRow(title: "Quit agymg", icon: "power", shortcut: "⌘Q", isHovered: isHoveredQuit, iconColor: Color.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: [.command])
            .onHover { isHoveredQuit = $0 }
            .help("Quit application (⌘Q)")
        }
    }

    private func actionRow(
        title: String,
        icon: String,
        shortcut: String,
        isHovered: Bool,
        iconColor: Color? = nil
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon).font(.system(size: 13))
                .foregroundStyle(iconColor ?? DesignTokens.secondary).frame(width: 18)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(DesignTokens.ink)
            Spacer()
            Text(shortcut).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.inkSecondary)
                .padding(.horizontal, DesignTokens.Spacing.xxs)
                .padding(.vertical, 2)
                .background(DesignTokens.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
        }
        .contentShape(Rectangle())
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .background(isHovered ? DesignTokens.surfaceContainerHigh : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
