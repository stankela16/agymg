import SwiftUI

public struct ControlCenterSidebar: View {
    @Bindable var state: AppState
    @Binding var selection: NavigationSection?
    @Environment(\.controlActiveState) private var controlActiveState

    public init(state: AppState, selection: Binding<NavigationSection?>) {
        self.state = state
        self._selection = selection
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBrand

            List(selection: $selection) {
                Section("CORE VAULT") {
                    navItem(title: "Master Vault", icon: "shield.lefthalf.filled", badge: "All Resources", section: .masterVault)
                    navItem(title: "Global Core", icon: "globe", badge: "Always Active", section: .globalCore)
                    navItem(title: "Plugins", icon: "puzzlepiece.extension", badge: "\(state.plugins.count) Packages", section: .plugins)
                    navItem(title: "System Built-ins", icon: "wrench.and.screwdriver", badge: "\(state.builtinSkills.count > 0 ? "\(state.builtinSkills.count)" : "18") Tools", section: .systemBuiltins)
                }

                Section {
                    if state.projects.isEmpty {
                        Text("No projects discovered")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.inkTertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(state.projects) { project in
                            projectRow(project: project)
                        }
                    }

                    if !state.isProjectsFolderAuthorized {
                        Button {
                            Task { await state.authorizeProjectsFolder() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus").font(.system(size: 13))
                                    .foregroundStyle(DesignTokens.tierOrange)
                                Text("Connect Projects Folder…").font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DesignTokens.tierOrange)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 8) {
                        Button {
                            state.openProjectDialog()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 12))
                                    .foregroundStyle(DesignTokens.secondary)
                                Text("Import Project…").font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DesignTokens.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Import any project folder from disk into agymg (⌘O)")

                        Spacer()

                        Button {
                            Task { await state.refreshProjects() }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.inkTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh project list and rescan workspace folder (⌘R)")
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("PROJECTS")
                        Spacer()
                        counterBadge("\(state.projects.count)", isSelected: false)
                    }
                }

                Section("SYSTEM") {
                    navItem(
                        title: "Sync Logs",
                        icon: "terminal",
                        badge: state.syncHistory.isEmpty ? "Ready" : "\(state.syncHistory.count)",
                        section: .syncLogs
                    )

                    let isSettings = selection == .settings
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                            .foregroundStyle(itemIconColor(isSelected: isSettings))
                        Text("Settings").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(itemTextColor(isSelected: isSettings))
                    }
                    .contentShape(Rectangle())
                    .tag(NavigationSection.settings)
                }
            }
            .listStyle(.sidebar)

            VaultEngineFooterView()
        }
        .background(DesignTokens.panel)
        .navigationSplitViewColumnWidth(
            min: DesignTokens.Dimensions.sidebarMinWidth,
            ideal: DesignTokens.Dimensions.sidebarIdealWidth,
            max: DesignTokens.Dimensions.sidebarMaxWidth
        )
    }

    private func navItem(title: String, icon: String, badge: String, section: NavigationSection) -> some View {
        let isSelected = selection == section
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13))
                .foregroundStyle(itemIconColor(isSelected: isSelected))
            Text(title).font(.system(size: 13, weight: .medium))
                .foregroundStyle(itemTextColor(isSelected: isSelected))
            Spacer()
            counterBadge(badge, isSelected: isSelected)
        }
        .contentShape(Rectangle())
        .tag(section)
    }

    private func projectRow(project: ProjectProfile) -> some View {
        let isSelected = selection == .project(project.id)
        return HStack(spacing: 8) {
            Circle()
                .fill(project.enabledMCPServerIds.isEmpty ? DesignTokens.tierOrange : DesignTokens.secondary)
                .frame(width: 7, height: 7)
            Text(project.name).font(.system(size: 13, weight: .medium))
                .foregroundStyle(itemTextColor(isSelected: isSelected)).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.inkTertiary)
        }
        .contentShape(Rectangle())
        .tag(NavigationSection.project(project.id))
        .contextMenu {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                state.openTerminal(for: project.path)
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }

            Divider()

            Button(role: .destructive) {
                Task { await state.removeProject(id: project.id) }
            } label: {
                Label("Remove from Manager", systemImage: "trash")
            }
        }
    }

    private var headerBrand: some View {
        HStack(spacing: 8) {
            AppLogoView(size: 24, cornerRadius: 5.5)
            VStack(alignment: .leading, spacing: 1) {
                Text("agymg").font(.system(size: 13, weight: .semibold)).foregroundStyle(DesignTokens.ink)
                Text("Native macOS Control Center").font(.system(size: 10)).foregroundStyle(DesignTokens.inkTertiary)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(DesignTokens.secondary).frame(width: 5, height: 5)
                Text("CORE OK").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(DesignTokens.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 2).background(DesignTokens.storeBlueTint).clipShape(Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(Divider().background(DesignTokens.hairline), alignment: .bottom)
    }

    private func itemTextColor(isSelected: Bool) -> Color {
        guard isSelected else { return DesignTokens.ink }
        return controlActiveState == .inactive ? DesignTokens.ink : Color.white
    }

    private func itemIconColor(isSelected: Bool) -> Color {
        guard isSelected else { return DesignTokens.primary }
        return controlActiveState == .inactive ? DesignTokens.primary : Color.white
    }

    private func counterBadge(_ count: String, isSelected: Bool = false) -> some View {
        let isWindowActive = controlActiveState != .inactive
        let bg = isSelected ? (isWindowActive ? Color.white.opacity(0.25) : DesignTokens.surfaceContainerHigh) : DesignTokens.surfaceContainerHigh
        let fg = isSelected ? (isWindowActive ? Color.white : DesignTokens.ink) : DesignTokens.inkSecondary
        return Text(count).font(.system(size: 10, weight: .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 2).background(bg).clipShape(Capsule())
    }
}
