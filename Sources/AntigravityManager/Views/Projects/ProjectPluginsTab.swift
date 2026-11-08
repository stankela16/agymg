import SwiftUI

public struct ProjectPluginsTab: View {
    @Bindable var state: AppState
    let projectId: String
    @Binding var deletionTarget: DeletionTarget?
    @State private var searchText: String = ""

    public init(
        state: AppState,
        projectId: String,
        deletionTarget: Binding<DeletionTarget?>
    ) {
        self.state = state
        self.projectId = projectId
        self._deletionTarget = deletionTarget
    }

    public init(
        state: AppState,
        project: ProjectProfile,
        deletionTarget: Binding<DeletionTarget?>
    ) {
        self.state = state
        self.projectId = project.id
        self._deletionTarget = deletionTarget
    }

    private var project: ProjectProfile? {
        state.projects.first(where: { $0.id == projectId })
    }

    private var filteredPlugins: [PluginDefinition] {
        state.plugins.filter { plugin in
            searchText.isEmpty ||
                plugin.name.localizedCaseInsensitiveContains(searchText) ||
                plugin.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        Group {
            if state.plugins.isEmpty {
                ContentUnavailableView(
                    "No Plugins Available",
                    systemImage: "puzzlepiece.extension",
                    description: Text("No plugins found in the Master Vault catalog.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    filterBar
                    Divider()

                    if filteredPlugins.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.xl)
                    } else {
                        pluginsGridView
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            SearchBarView(text: $searchText, placeholder: "Search plugins...")
                .frame(maxWidth: 320)
            Spacer()
            Text("\(filteredPlugins.count) of \(state.plugins.count)")
                .font(.caption).monospacedDigit().foregroundStyle(DesignTokens.inkSecondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var pluginsGridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
            ForEach(filteredPlugins) { plugin in
                pluginCard(for: plugin)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func pluginCard(for plugin: PluginDefinition) -> some View {
        let isGlobal = state.globalPluginIds.contains(plugin.id)
        let isProjectEnabled = project?.enabledPluginIds.contains(plugin.id) ?? false
        let projectName = project?.name ?? "project"

        return ResourceCardView(
            title: plugin.name,
            subtitle: plugin.id,
            summary: "Plugin package at \(plugin.path)",
            iconName: "puzzlepiece.extension.fill",
            iconGradient: DesignTokens.Gradients.vault,
            badges: {
                if plugin.hasMCP { ResourcePillBadge.mcpBundle }
                if plugin.hasSkills { ResourcePillBadge.skillsBundle }
                if isGlobal {
                    ResourcePillBadge.global
                        .help("Already enabled globally across all workspaces via Global Core")
                }
                if isProjectEnabled {
                    ResourcePillBadge.linkedToProject
                        .help("Symlink created inside \(projectName)/.agents/plugins/")
                }
            },
            actions: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal plugin folder in Finder")

                    if isGlobal {
                        Toggle("", isOn: .constant(true))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(DesignTokens.primaryContainer)
                            .disabled(true)
                            .help("Enabled globally via Global Core (available across all projects). Manage in Global Core.")
                    } else {
                        Toggle("", isOn: Binding(
                            get: { project?.enabledPluginIds.contains(plugin.id) ?? false },
                            set: { _ in state.toggleProjectPlugin(projectId: projectId, pluginId: plugin.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .help(isProjectEnabled ? "Remove plugin symlink from project" : "Create symlink in \(projectName)/.agents/plugins/")
                    }
                }
            }
        )
        .contextMenu {
            Button(role: .destructive) {
                deletionTarget = .plugin(plugin)
            } label: {
                Label("Uninstall from Mac…", systemImage: "trash")
            }
        }
    }
}
