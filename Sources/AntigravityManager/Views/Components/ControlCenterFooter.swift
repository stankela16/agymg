import SwiftUI

public struct ControlCenterFooter: View {
    let state: AppState

    public init(state: AppState) {
        self.state = state
    }

    private var statusDotColor: Color {
        if state.isSyncing {
            return DesignTokens.tierOrange
        }
        if state.syncHistory.first?.status == .failure {
            return DesignTokens.Colors.statusError
        }
        return DesignTokens.secondary
    }

    private var statusBadgeTitle: String {
        if state.isSyncing { return "SYNCING" }
        if state.syncHistory.first?.status == .failure { return "ERROR" }
        return "LIVE"
    }

    private var statusBadgeBackground: Color {
        if state.isSyncing { return DesignTokens.tierOrange.opacity(0.12) }
        if state.syncHistory.first?.status == .failure { return DesignTokens.Colors.statusError.opacity(0.12) }
        return DesignTokens.storeBlueTint
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Live status dot and title
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text("Antigravity Engine")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
            }

            Text(statusBadgeTitle)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(statusDotColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(statusBadgeBackground)
                .clipShape(Capsule())

            // Real Live Metrics
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text("\(state.servers.count) MCPs")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                    Text("•").foregroundStyle(DesignTokens.inkTertiary)
                    Text("\(state.skills.count) Skills")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                    Text("•").foregroundStyle(DesignTokens.inkTertiary)
                    Text("\(state.plugins.count) Plugins")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                    Text("•").foregroundStyle(DesignTokens.inkTertiary)
                    Text("\(state.projects.count) Projects")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }

                HStack(spacing: 6) {
                    Text("\(state.servers.count) MCP")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkSecondary)
                    Text("•").foregroundStyle(DesignTokens.inkTertiary)
                    Text("\(state.skills.count) Sk")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkSecondary)
                    Text("•").foregroundStyle(DesignTokens.inkTertiary)
                    Text("\(state.plugins.count) Pl")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkSecondary)
                    Text("•").foregroundStyle(DesignTokens.inkTertiary)
                    Text("\(state.projects.count) Pr")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }

                Text("\(state.servers.count) MCPs • \(state.projects.count) Projects")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.inkSecondary)
            }

            Spacer()

            // Dynamic status message or last sync
            if let status = state.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let lastSync = state.lastSyncDate {
                Text("Synced: \(lastSync.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .lineLimit(1)
            }

            // Action Buttons
            HStack(spacing: 8) {
                Button {
                    state.navigationSelection = .syncLogs
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11))
                        Text("View Logs")
                            .font(.system(size: 12, weight: .medium))
                        if !state.syncHistory.isEmpty {
                            Text("\(state.syncHistory.count)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(DesignTokens.surfaceContainerHigh)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DesignTokens.surfaceContainerLow)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(DesignTokens.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("View synchronization history (⌘5)")

                Button {
                    state.syncAll()
                } label: {
                    HStack(spacing: 4) {
                        if state.isSyncing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                        }
                        Text(state.isSyncing ? "Syncing..." : "Sync All")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(DesignTokens.primaryContainer)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(state.isSyncing)
                .help("Synchronize all global and project resources (⌘S)")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, 12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.default))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.default)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.md)
    }
}
