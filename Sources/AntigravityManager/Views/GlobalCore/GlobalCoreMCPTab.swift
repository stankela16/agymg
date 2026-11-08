import SwiftUI

public struct GlobalCoreMCPTab: View {
    @Bindable var state: AppState
    @Binding var deletionTarget: DeletionTarget?
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var serverToEdit: MCPServerDefinition? = nil
    @State private var showingAddServer: Bool = false

    public init(state: AppState, deletionTarget: Binding<DeletionTarget?>) {
        self.state = state
        self._deletionTarget = deletionTarget
    }

    private var mcpCategories: [String] {
        var cats = Set(state.servers.map { $0.category })
        cats.insert("All")
        return ["All"] + cats.filter { $0 != "All" }.sorted()
    }

    private var categoryCounts: [String: Int] {
        var dict: [String: Int] = ["All": state.servers.count]
        for cat in mcpCategories where cat != "All" {
            dict[cat] = state.servers.filter { $0.category == cat }.count
        }
        return dict
    }

    private var filteredServers: [MCPServerDefinition] {
        state.servers.filter { server in
            let matchesCategory = selectedCategory == "All" || server.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                server.name.localizedCaseInsensitiveContains(searchText) ||
                server.id.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            filterBar

            if filteredServers.isEmpty {
                emptyView
                    .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                serversGridView
            }
        }
        .sheet(item: $serverToEdit) { server in
            EditMCPServerSheet(state: state, server: server, addToGlobal: true)
        }
        .sheet(isPresented: $showingAddServer) {
            EditMCPServerSheet(state: state, addToGlobal: true)
        }
    }

    private var filterBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            FilterChipsView(
                categories: mcpCategories,
                counts: categoryCounts,
                selectedCategory: $selectedCategory,
                searchText: $searchText,
                placeholder: "Filter global connectors..."
            )
            Spacer()
            Button {
                showingAddServer = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Server")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primaryContainer)
            .help("Add a new MCP server to Global Core")
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var emptyView: some View {
        Group {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView(
                    "No MCP Servers",
                    systemImage: "point.3.filled.connected.trianglepath",
                    description: Text("No global MCP servers found in this category.")
                )
            }
        }
        .frame(maxWidth: .infinity)
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
        let isActive = state.globalServerIds.contains(server.id)

        return ResourceCardView(
            title: server.name,
            subtitle: server.command ?? server.serverUrl ?? server.id,
            summary: server.summary,
            iconName: DesignTokens.Gradients.iconForCategory(server.category),
            iconGradient: DesignTokens.Gradients.forCategory(server.category),
            badges: {
                if isActive { ResourcePillBadge.global }
            },
            actions: {
                Toggle("", isOn: Binding(
                    get: { isActive },
                    set: { _ in state.toggleGlobalServer(id: server.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.primaryContainer)
                .help(isActive ? "Disable global MCP server" : "Enable global MCP server")
            }
        )
        .contextMenu {
            Button {
                serverToEdit = server
            } label: {
                Label("Edit…", systemImage: "pencil.line")
            }
            Divider()
            Button(role: .destructive) {
                deletionTarget = .server(server)
            } label: {
                Label("Uninstall from Mac…", systemImage: "trash")
            }
        }
    }
}
