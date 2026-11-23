import SwiftUI

public struct VaultEngineFooterView: View {
    var state: AppState? = nil

    public init(state: AppState? = nil) {
        self.state = state
    }

    private var statusBadge: (label: String, color: Color, background: Color) {
        guard let state else {
            return ("READY", DesignTokens.Colors.statusSuccess, DesignTokens.Colors.statusSuccessBg)
        }
        if state.isSyncing {
            return ("SYNCING", DesignTokens.tierOrange, DesignTokens.tierOrange.opacity(0.14))
        }
        let activeServerIds = state.globalServerIds.union(state.projects.flatMap(\.enabledMCPServerIds))
        let activeHealth = state.mcpHealthByServerId.filter { activeServerIds.contains($0.key) }.values
        let auditFailed = state.projectSafetyAudits.values.filter { $0.overallStatus == .failed }.count
        let mcpErrors = activeHealth.filter { $0.state == .error }.count
        let driftErrors = state.driftIssues.filter { $0.severity == .error }.count
        let totalErrors = auditFailed + mcpErrors + driftErrors
        if totalErrors > 0 {
            return ("\(totalErrors) ERR", DesignTokens.Colors.statusError, DesignTokens.Colors.statusErrorBg)
        }

        let auditWarn = state.projects.filter { proj in
            !proj.enabledMCPServerIds.isEmpty && state.projectSafetyAudits[proj.id]?.overallStatus == .warning
        }.count
        let mcpWarnings = activeHealth.filter { $0.state == .warning }.count
        let driftWarnings = state.driftIssues.filter { $0.severity == .warning }.count
        let totalWarnings = auditWarn + mcpWarnings + driftWarnings
        if totalWarnings > 0 {
            return ("\(totalWarnings) WARN", DesignTokens.tierOrange, DesignTokens.tierOrange.opacity(0.14))
        }
        return ("READY", DesignTokens.Colors.statusSuccess, DesignTokens.Colors.statusSuccessBg)
    }

    public var body: some View {
        let status = statusBadge
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("VAULT ENGINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
                Spacer()
                Text(status.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(status.background)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("~/.gemini/manager-vault/")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignTokens.inkTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                Circle().fill(status.color).frame(width: 5, height: 5)
                Text(state?.isSyncing == true ? "Synchronizing..." : "Connected")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkSecondary)
                Spacer()
            }
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
        .padding(8)
    }
}
