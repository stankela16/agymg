import SwiftUI
import ServiceManagement

public struct SettingsGeneralTab: View {
    @Bindable var state: AppState
    @State private var launchManager = LaunchAtLoginManager.shared

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "power")
                            .foregroundStyle(DesignTokens.secondary)
                        Text("Launch at Login (App Review Guideline 2.4.5)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.ink)
                    }

                    Text("Starts agymg automatically in the menu bar when you sign in to macOS, keeping your Vault sync engine and status popover available at a glance.")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Toggle("Launch at login", isOn: Binding(
                            get: { launchManager.isEnabled },
                            set: { launchManager.isEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Spacer()

                        statusBadge(for: launchManager.status)
                    }
                    .padding(.top, DesignTokens.Spacing.xxs)

                    if launchManager.status == .requiresApproval {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DesignTokens.tierOrange)
                            Text("Approval required in macOS System Settings.")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.tierOrange)
                            Spacer()
                            Button("Open Login Items…") {
                                launchManager.openSystemLoginItemsSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(DesignTokens.Spacing.xs)
                        .background(DesignTokens.tierOrange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
                    }

                    if launchManager.status == .notFound {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(DesignTokens.inkTertiary)
                            Text("Install agymg.app into /Applications (or run `agymg install-app`) to enable Launch at Login.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(DesignTokens.inkSecondary)
                        }
                        .padding(DesignTokens.Spacing.xs)
                        .background(DesignTokens.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
                    }

                    if let error = launchManager.lastErrorMessage {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(DesignTokens.Colors.statusError)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.statusError)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            } header: {
                Text("System Startup")
            }

            Section {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack {
                        Text("Control Center Shortcut:")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.ink)
                        Spacer()
                        Text("⌘0 / ⌃⌥A")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Text("Press ⌃⌥A globally (or ⌘0 inside the app) to bring the Control Center window to the front.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)
            } header: {
                Text("Keyboard Shortcuts")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchManager.refresh()
        }
    }

    private func statusBadge(for status: SMAppService.Status) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 6, height: 6)
            Text(statusTitle(for: status))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor(for: status))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor(for: status).opacity(0.12))
        .clipShape(Capsule())
    }

    private func statusColor(for status: SMAppService.Status) -> Color {
        switch status {
        case .enabled: return DesignTokens.secondary
        case .requiresApproval: return DesignTokens.tierOrange
        case .notRegistered: return DesignTokens.steel
        case .notFound: return DesignTokens.inkTertiary
        @unknown default: return DesignTokens.inkTertiary
        }
    }

    private func statusTitle(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "ENABLED"
        case .requiresApproval: return "APPROVAL NEEDED"
        case .notRegistered: return "DISABLED"
        case .notFound: return "UNREGISTERED"
        @unknown default: return "UNKNOWN"
        }
    }
}
