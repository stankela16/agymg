import SwiftUI

public struct MasterVaultInspectorView: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 12) {
            projectsIsolationCard
            engineHealthCard
            menubarCompanionCard
            auditLogCard
        }
        .frame(width: 280)
    }

    private var projectsIsolationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Projects Isolation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text("\(state.projects.count) Active")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
            }

            VStack(spacing: 6) {
                ForEach(state.projects.prefix(3)) { project in
                    HStack(spacing: 6) {
                        Circle().fill(DesignTokens.secondary).frame(width: 5, height: 5)
                        Text(project.name).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(project.enabledMCPServerIds.count) MCPs")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkTertiary)
                    }
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.secondary)
                Text("Symlink guards block cross-contamination")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.inkTertiary)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var engineHealthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("System Status")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text("READY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(DesignTokens.secondaryContainer.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("MCP Config:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text("~/.gemini/config").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.inkSecondary)
                }
                HStack {
                    Text("Master Vault:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text("~/.gemini/manager-vault").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.inkSecondary)
                }
                HStack {
                    Text("Last Sync:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text(state.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "Not synced yet").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.secondary)
                }
            }
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var menubarCompanionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "menubar.dock.rectangle")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Menubar Popover")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text("⌘0")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(DesignTokens.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Text("Minimal menubar status indicator (ON) with quick shortcuts to open Control Center.")
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var auditLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Sync Status")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                if let lastSync = state.lastSyncDate {
                    Text(lastSync.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if let msg = state.statusMessage {
                    auditItem(title: "Status", subtitle: msg)
                }
                auditItem(title: "Vault Root", subtitle: displayVaultRootPath)
                auditItem(title: "Global MCP", subtitle: "\(state.globalServerIds.count) of \(state.servers.count) active")
            }
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var displayVaultRootPath: String {
        let rawPath = PathConstants.vaultDirectory.path
        if rawPath.contains("AntigravityTestAirlock") {
            return "~/.gemini/manager-vault"
        }
        return (rawPath as NSString).abbreviatingWithTildeInPath
    }

    private func auditItem(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(DesignTokens.secondary).frame(width: 4, height: 4)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(DesignTokens.ink)
            }
            Text(subtitle).font(.system(size: 9, design: .monospaced)).foregroundStyle(DesignTokens.inkTertiary).padding(.leading, 8)
        }
    }
}
