import SwiftUI

public struct OnboardingFeatureList: View {
    public init() {}

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            OnboardingFeatureRow(
                icon: "sparkles",
                iconColor: DesignTokens.secondary,
                title: "Automatic Workspace Discovery",
                description: "Detects git repositories in your chosen projects folder and imports existing Claude Code & Antigravity setups automatically."
            )
            OnboardingFeatureRow(
                icon: "shield.lefthalf.filled",
                iconColor: DesignTokens.primary,
                title: "Per-Project MCP & Skill Isolation",
                description: "Loads only the tools each repository needs, keeping context windows lean and protecting tokens in .gitignore."
            )
            OnboardingFeatureRow(
                icon: "lock.shield",
                iconColor: DesignTokens.tierOrange,
                title: "Persistent Security-Scoped Bookmark",
                description: "Remembers folder permission natively on macOS so you never get repeated system permission prompts."
            )
        }
        .frame(maxWidth: 540)
    }
}
