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
        let totalServers = state.servers.count
        let healthValues = Array(state.mcpHealthByServerId.values)
        let errorCount = healthValues.filter { $0.state == .error }.count
        let warnCount = healthValues.filter { $0.state == .warning }.count
        let healthyCount = max(0, totalServers - errorCount - warnCount)
        let driftCount = state.driftIssues.count

        let badgeTitle: String = {
            if errorCount > 0 { return "\(errorCount) ERR" }
            if warnCount > 0 || driftCount > 0 { return "\(warnCount + driftCount) WARN" }
            return "READY"
        }()
        let badgeColor: Color = errorCount > 0
            ? DesignTokens.Colors.statusError
            : ((warnCount > 0 || driftCount > 0) ? DesignTokens.tierOrange : DesignTokens.Colors.statusSuccess)
        let badgeBg: Color = errorCount > 0
            ? DesignTokens.Colors.statusErrorBg
            : ((warnCount > 0 || driftCount > 0) ? DesignTokens.Colors.statusWarningBg : DesignTokens.Colors.statusSuccessBg)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: errorCount > 0 ? "xmark.octagon.fill" : ((warnCount > 0 || driftCount > 0) ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                        .font(.system(size: 12))
                        .foregroundStyle(badgeColor)
                    Text("System Status")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Button {
                    Task { await state.refreshDiagnostics() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
                .buttonStyle(.plain)
                .help("Re-run MCP health and config drift checks")

                Text(badgeTitle)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(badgeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("MCP Health:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text("\(healthyCount)/\(totalServers) OK")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(errorCount > 0 ? DesignTokens.Colors.statusError : (warnCount > 0 ? DesignTokens.tierOrange : DesignTokens.Colors.statusSuccess))
                }
                HStack {
                    Text("Config Drift:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text(driftCount == 0 ? "In sync" : "\(driftCount) \(driftCount == 1 ? "issue" : "issues")")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(driftCount == 0 ? DesignTokens.secondary : DesignTokens.tierOrange)
                }
                HStack {
                    Text("Last Sync:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text(state.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "Not synced yet").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.secondary)
                }
            }

            if driftCount > 0 {
                Button {
                    state.syncAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Fix Drift (Sync All)")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.primaryContainer)
                .controlSize(.mini)
                .help(state.driftIssues.prefix(3).map(\.detail).joined(separator: "\n"))
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
