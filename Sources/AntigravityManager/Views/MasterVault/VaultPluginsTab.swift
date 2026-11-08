import SwiftUI
import AppKit

public struct VaultPluginsTab: View {
    @Bindable var state: AppState
    @Binding var deletionTarget: DeletionTarget?
    @State private var searchText: String = ""

    public init(state: AppState, deletionTarget: Binding<DeletionTarget?>) {
        self.state = state
        self._deletionTarget = deletionTarget
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
                    "No Plugins",
                    systemImage: "puzzlepiece",
                    description: Text("Master Vault contains no installed plugins.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    searchBarSection
                    Divider()

                    if filteredPlugins.isEmpty {
                        emptyView
                            .padding(.vertical, DesignTokens.Spacing.xl)
                    } else {
                        pluginsGridView
                    }
                }
            }
        }
    }

    private var searchBarSection: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            SearchBarView(text: $searchText, placeholder: "Search installed plugins...")
                .frame(maxWidth: 320)
            Spacer()
            Text("\(filteredPlugins.count) of \(state.plugins.count)")
                .font(.caption).monospacedDigit().foregroundStyle(DesignTokens.inkSecondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var emptyView: some View {
        ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity)
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
        let activeProjects = state.projects.filter { $0.enabledPluginIds.contains(plugin.id) }

        return ResourceCardView(
            title: plugin.name,
            subtitle: plugin.path,
            summary: "Plugin package with ID: \(plugin.id)",
            iconName: "puzzlepiece.extension.fill",
            iconGradient: DesignTokens.Gradients.vault,
            badges: {
                if plugin.hasMCP { ResourcePillBadge.mcpBundle }
                if plugin.hasSkills { ResourcePillBadge.skillsBundle }
                if isGlobal {
                    ResourcePillBadge.global
                        .help("Active across all workspaces (managed in Global Core)")
                }
                if !activeProjects.isEmpty {
                    ResourcePillBadge.scopedProjects(activeProjects.count)
                        .help("Active in: \(activeProjects.map(\.name).joined(separator: ", "))")
                }
                if !isGlobal && activeProjects.isEmpty {
                    ResourcePillBadge.catalogOnly
                        .help("Stored in Master Vault catalog, currently inactive globally and per-project")
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
                    .help("Reveal in Finder")

                    Button(role: .destructive) {
                        deletionTarget = .plugin(plugin)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Uninstall \(plugin.name) from Mac")
                }
            }
        )
        .contextMenu {
            Button {
                NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }
            Divider()
            Button(role: .destructive) {
                deletionTarget = .plugin(plugin)
            } label: {
                Label("Uninstall from Mac…", systemImage: "trash")
            }
        }
    }
}
