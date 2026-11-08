import SwiftUI

public struct OnboardingSuccessBadge: View {
    public let projectCount: Int
    public let projectNames: [String]
    public let onContinue: () -> Void

    public init(projectCount: Int, projectNames: [String], onContinue: @escaping () -> Void) {
        self.projectCount = projectCount
        self.projectNames = projectNames
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.green.opacity(0.3), radius: 12)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.green)
            }

            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text("Workspace Connected!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DesignTokens.ink)

                Text("Folder access has been authorized and saved via a macOS security-scoped bookmark.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.inkSecondary)
            }

            if projectCount > 0 {
                VStack(spacing: DesignTokens.Spacing.xxs) {
                    Text("Discovered \(projectCount) \(projectCount == 1 ? "project" : "projects") in your workspace:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.inkTertiary)

                    let previewNames = projectNames.prefix(5).joined(separator: ", ")
                    Text(previewNames + (projectNames.count > 5 ? " and \(projectNames.count - 5) more..." : ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Button {
                onContinue()
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("Open Control Center")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.green)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .help("Finish setup and open the Control Center")
        }
        .padding(DesignTokens.Spacing.xl)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                .strokeBorder(Color.green.opacity(0.3), lineWidth: 1.5)
        )
    }
}
