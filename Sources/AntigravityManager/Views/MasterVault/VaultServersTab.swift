import SwiftUI
import AppKit

public struct VaultServersTab: View {
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            filterBarSection

            if filteredServers.isEmpty {
                emptyView
                    .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                serversGridView
            }
        }
        .sheet(item: $serverToEdit) { server in
            EditMCPServerSheet(state: state, server: server)
        }
        .sheet(isPresented: $showingAddServer) {
            EditMCPServerSheet(state: state)
        }
    }

    private var filterBarSection: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            FilterChipsView(
                categories: serverCategories,
                counts: categoryCounts,
                selectedCategory: $selectedCategory,
                searchText: $searchText,
                placeholder: "Filter vault servers..."
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
            .help("Add a new MCP server to Master Vault")
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var emptyView: some View {
        Group {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if state.servers.isEmpty {
                EmptyStateView.emptyServers
            } else {
                ContentUnavailableView(
                    "No MCP Servers",
                    systemImage: "server.rack",
                    description: Text("No MCP servers found in category \"\(selectedCategory)\".")
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
        let isGlobal = state.globalServerIds.contains(server.id)
        let activeProjects = state.projects.filter { $0.enabledMCPServerIds.contains(server.id) }

        return ResourceCardView(
            title: server.name,
            subtitle: server.command ?? server.serverUrl ?? server.id,
            summary: server.summary,
            iconName: DesignTokens.Gradients.iconForCategory(server.category),
            iconGradient: DesignTokens.Gradients.forCategory(server.category),
            badges: {
                ResourcePillBadge.category(server.category)
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
                        serverToEdit = server
                    } label: {
                        Image(systemName: "pencil.line")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit MCP server configuration")

                    if let cmd = server.command, cmd.contains("/") {
                        Button {
                            let path = cmd.split(separator: " ").first.map(String.init) ?? cmd
                            if FileManager.default.fileExists(atPath: path) {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            }
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal executable path in Finder")
                    }

                    Button(role: .destructive) {
                        deletionTarget = .server(server)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color(hex: 0xF5222D))
                    }
                    .buttonStyle(.borderless)
                    .help("Uninstall MCP server from Mac")
                }
            }
        )
        .contextMenu {
            Button {
                serverToEdit = server
            } label: {
                Label("Edit Configuration…", systemImage: "pencil.line")
            }
            if let cmd = server.command ?? server.serverUrl {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                } label: {
                    Label("Copy Command / URL", systemImage: "doc.on.doc")
                }
            }
            if let cmd = server.command, cmd.contains("/") {
                Button {
                    let path = cmd.split(separator: " ").first.map(String.init) ?? cmd
                    if FileManager.default.fileExists(atPath: path) {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
                }
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
