import SwiftUI

public struct OnboardingHeaderView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(DesignTokens.secondary.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DesignTokens.secondary)
            }

            Text("Connect Your Projects Folder")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DesignTokens.ink)

            Text("Authorize your root projects directory (e.g. ~/Projects or ~/Developer) so agymg can discover repositories and synchronize per-project MCP servers, skills, and plugins across Claude Code and Antigravity.")
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
        }
    }
}
