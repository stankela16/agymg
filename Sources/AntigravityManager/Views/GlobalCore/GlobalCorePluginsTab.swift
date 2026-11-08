import SwiftUI

public struct GlobalCorePluginsTab: View {
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
                    "No Plugins Installed",
                    systemImage: "puzzlepiece.extension",
                    description: Text("No plugins found in the Master Vault catalog.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    filterBar
                    Divider()
                    pluginsGridView
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
        let isActive = state.globalPluginIds.contains(plugin.id)

        return ResourceCardView(
            title: plugin.name,
            subtitle: plugin.id,
            summary: "Global plugin at \(plugin.path)",
            iconName: "puzzlepiece.extension.fill",
            iconGradient: DesignTokens.Gradients.vault,
            badges: {
                if plugin.hasMCP { ResourcePillBadge.mcpBundle }
                if plugin.hasSkills { ResourcePillBadge.skillsBundle }
                if isActive { ResourcePillBadge.global }
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

                    Toggle("", isOn: Binding(
                        get: { isActive },
                        set: { _ in state.toggleGlobalPlugin(id: plugin.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(isActive ? "Disable global plugin" : "Enable global plugin")
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
