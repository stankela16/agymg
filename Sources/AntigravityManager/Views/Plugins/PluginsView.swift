import SwiftUI
import AppKit

public struct PluginsView: View {
    @Bindable var state: AppState
    @Binding var deletionTarget: DeletionTarget?
    @State private var searchText: String = ""
    @State private var selectedFilter: String = "All"

    public init(state: AppState, deletionTarget: Binding<DeletionTarget?>) {
        self.state = state
        self._deletionTarget = deletionTarget
    }

    private var filteredPlugins: [PluginDefinition] {
        state.plugins.filter { plugin in
            let matchesSearch = searchText.isEmpty ||
                plugin.name.localizedCaseInsensitiveContains(searchText) ||
                plugin.id.localizedCaseInsensitiveContains(searchText) ||
                plugin.description.localizedCaseInsensitiveContains(searchText)
            guard matchesSearch else { return false }

            switch selectedFilter {
            case "Global": return state.globalPluginIds.contains(plugin.id)
            case "Has MCP": return plugin.hasMCP
            case "Has Skills": return plugin.hasSkills
            default: return true
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            heroBanner
            filterSection
            Divider()
            contentBody
        }
    }

    private var heroBanner: some View {
        HeroBannerView(
            title: "Plugins & Extensions",
            subtitle: "Modular packages bundling MCP connectors and skills in ~/.gemini/manager-vault/plugins/",
            iconName: "puzzlepiece.extension.fill",
            iconGradient: DesignTokens.Gradients.vault,
            revealPath: PathConstants.vaultPluginsDirectory.path,
            stats: [
                HeroBannerStatItem(label: "Installed Plugins", value: "\(state.plugins.count)", icon: "puzzlepiece.extension", tint: DesignTokens.primary, subtitle: "Available on Mac"),
                HeroBannerStatItem(label: "Global Active", value: "\(state.globalPluginIds.count)", icon: "globe", tint: DesignTokens.primary, subtitle: "Enabled everywhere"),
                HeroBannerStatItem(label: "Bundled MCP", value: "\(state.plugins.filter(\.hasMCP).count)", icon: "point.3.filled.connected.trianglepath", tint: DesignTokens.primary, subtitle: "Contain servers"),
                HeroBannerStatItem(label: "Bundled Skills", value: "\(state.plugins.filter(\.hasSkills).count)", icon: "brain.head.profile", tint: DesignTokens.primary, subtitle: "Contain runbooks")
            ]
        )
    }

    private var filterSection: some View {
        FilterChipsView(
            categories: ["All", "Global", "Has MCP", "Has Skills"],
            counts: [
                "All": state.plugins.count,
                "Global": state.globalPluginIds.count,
                "Has MCP": state.plugins.filter(\.hasMCP).count,
                "Has Skills": state.plugins.filter(\.hasSkills).count
            ],
            selectedCategory: $selectedFilter,
            searchText: $searchText,
            placeholder: "Search installed plugins..."
        )
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    @ViewBuilder
    private var contentBody: some View {
        if state.plugins.isEmpty {
            ContentUnavailableView(
                "No Plugins Installed",
                systemImage: "puzzlepiece.extension",
                description: Text("No plugin packages found in Vault or projects.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredPlugins.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)],
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(filteredPlugins) { plugin in
                        pluginCard(for: plugin)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
    }

    private func pluginCard(for plugin: PluginDefinition) -> some View {
        let isGlobal = state.globalPluginIds.contains(plugin.id)
        let linkedProjects = state.projects.filter { $0.enabledPluginIds.contains(plugin.id) }

        return ResourceCardView(
            title: plugin.name,
            subtitle: plugin.path,
            summary: plugin.description.isEmpty ? "Plugin package with ID: \(plugin.id)" : plugin.description,
            iconName: "puzzlepiece.extension.fill",
            iconGradient: DesignTokens.Gradients.vault,
            badges: {
                if plugin.hasMCP { ResourcePillBadge.mcpBundle }
                if plugin.hasSkills { ResourcePillBadge.skillsBundle }
                if isGlobal { ResourcePillBadge.global }
                if !linkedProjects.isEmpty {
                    ResourcePillBadge(title: "\(linkedProjects.count) Proj", color: DesignTokens.djiBlue)
                }
            },
            actions: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if !state.projects.isEmpty {
                        Menu {
                            Text("Enable for workspaces:")
                            ForEach(state.projects) { proj in
                                Toggle(proj.name, isOn: Binding(
                                    get: { proj.enabledPluginIds.contains(plugin.id) },
                                    set: { _ in state.toggleProjectPlugin(projectId: proj.id, pluginId: plugin.id) }
                                ))
                            }
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Toggle plugin for individual projects")
                    }

                    Button {
                        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")

                    Toggle("", isOn: Binding(
                        get: { isGlobal },
                        set: { _ in state.toggleGlobalPlugin(id: plugin.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(isGlobal ? "Disable global plugin" : "Enable global plugin")
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
