import SwiftUI

public struct ProjectServersTab: View {
    @Bindable var state: AppState
    let projectId: String
    @Binding var deletionTarget: DeletionTarget?
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

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

    private var serverCategories: [String] {
        var cats = Set(state.servers.map { $0.category })
        cats.insert("All")
        return ["All"] + cats.filter { $0 != "All" }.sorted()
    }

    private var categoryCounts: [String: Int] {
        var dict: [String: Int] = ["All": state.servers.count]
        for cat in serverCategories where cat != "All" {
            dict[cat] = state.servers.filter { $0.category == cat }.count
        }
        return dict
    }

    private var filteredServers: [MCPServerDefinition] {
        state.servers.filter { server in
            let matchesCategory = selectedCategory == "All" || server.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                server.name.localizedCaseInsensitiveContains(searchText) ||
                server.id.localizedCaseInsensitiveContains(searchText) ||
                server.summary.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        Group {
            if state.servers.isEmpty {
                ContentUnavailableView(
                    "No MCP Servers",
                    systemImage: "point.3.filled.connected.trianglepath",
                    description: Text("Master Vault contains no installed MCP servers.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    filterBar

                    if filteredServers.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.xl)
                    } else {
                        serversGridView
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        FilterChipsView(
            categories: serverCategories,
            counts: categoryCounts,
            selectedCategory: $selectedCategory,
            searchText: $searchText,
            placeholder: "Filter resources..."
        )
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var serversGridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
            ForEach(filteredServers) { server in
                serverCard(for: server)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func serverCard(for server: MCPServerDefinition) -> some View {
        let isGlobal = state.globalServerIds.contains(server.id)
        let isProjectEnabled = project?.enabledMCPServerIds.contains(server.id) ?? false
        let projectName = project?.name ?? "project"

        return ResourceCardView(
            title: server.name,
            subtitle: server.command ?? server.serverUrl ?? server.id,
            summary: server.summary,
            iconName: DesignTokens.Gradients.iconForCategory(server.category),
            iconGradient: DesignTokens.Gradients.forCategory(server.category),
            badges: {
                if isGlobal {
                    ResourcePillBadge.global
                        .help("Already enabled globally across all workspaces via Global Core")
                }
                if isProjectEnabled {
                    ResourcePillBadge.projectPlugin
                        .help("Isolated for this project inside .agents/plugins/")
                }
            },
            actions: {
                if isGlobal {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(DesignTokens.primaryContainer)
                        .disabled(true)
                        .help("Enabled globally via Global Core (available across all projects). Manage in Global Core.")
                } else {
                    Toggle("", isOn: Binding(
                        get: { project?.enabledMCPServerIds.contains(server.id) ?? false },
                        set: { _ in state.toggleProjectServer(projectId: projectId, serverId: server.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DesignTokens.primaryContainer)
                    .help(isProjectEnabled ? "Disable MCP server for this project" : "Enable MCP server for \(projectName)")
                }
            }
        )
        .contextMenu {
            Button(role: .destructive) {
                deletionTarget = .server(server)
            } label: {
                Label("Uninstall from Mac…", systemImage: "trash")
            }
        }
    }
}
