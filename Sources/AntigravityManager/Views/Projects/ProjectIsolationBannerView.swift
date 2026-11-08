import SwiftUI

public struct ProjectIsolationBannerView: View {
    public let projectName: String

    public init(projectName: String) {
        self.projectName = projectName
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignTokens.secondaryContainer.opacity(0.35))
                    .frame(width: 32, height: 32)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.secondary)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("Project Scope for \(projectName)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.ink)

                    Text("ISOLATED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.secondaryContainer.opacity(0.35))
                        .clipShape(Capsule())
                }

                Text("Tools enabled here apply exclusively to this workspace via .agents/plugins/, .agents/skills/, and .claude/skills/. Globally enabled tools are automatically inherited without extra configuration.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }
}
