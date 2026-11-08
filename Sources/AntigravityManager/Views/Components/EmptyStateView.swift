import SwiftUI

public struct EmptyStateView: View {
    public let title: String
    public let systemImage: String
    public let description: String?

    public init(title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    public var body: some View {
        if let description {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            ContentUnavailableView(title, systemImage: systemImage)
        }
    }

    // MARK: - Convenience Presets
    public static var noProjectSelected: some View {
        ContentUnavailableView(
            "Select a Project",
            systemImage: "sidebar.left",
            description: Text("Select a project from the sidebar to configure per-project MCP servers, skills, and plugins.")
        )
    }

    public static func searchEmpty(query: String) -> some View {
        ContentUnavailableView.search(text: query)
    }

    public static var emptyVault: some View {
        ContentUnavailableView(
            "Master Vault Is Empty",
            systemImage: "lock.shield",
            description: Text("No MCP servers or skills are currently installed in the catalog.")
        )
    }

    public static var emptySkills: some View {
        ContentUnavailableView(
            "No Skills Found",
            systemImage: "puzzlepiece.fill",
            description: Text("No installed skills match the current filter.")
        )
    }

    public static var emptyServers: some View {
        ContentUnavailableView(
            "No MCP Servers Found",
            systemImage: "server.rack",
            description: Text("No installed MCP servers match the current filter.")
        )
    }
}
