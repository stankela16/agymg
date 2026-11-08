import SwiftUI

public struct VaultGuidanceBannerView: View {
    var state: AppState? = nil

    public init(state: AppState? = nil) {
        self.state = state
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignTokens.storeBlueTint)
                    .frame(width: 32, height: 32)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.secondary)
            }
            .overlay(Circle().strokeBorder(DesignTokens.secondary.opacity(0.2), lineWidth: 1))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("Master Vault is the central catalog of all installed resources")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.ink)

                    Text("CATALOG")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.secondaryContainer.opacity(0.35))
                        .clipShape(Capsule())
                }

                Text("This list represents the complete catalog of tools stored in ~/.gemini/manager-vault/. Nothing runs inside Master Vault directly — enable and scope tools in dedicated sections:")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DesignTokens.Spacing.md) {
                    if let state {
                        Button {
                            state.navigationSelection = .globalCore
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xxs) {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.tierOrange)
                                Text("Global Core:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(DesignTokens.ink)
                                Text("Always active across all workspaces")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.inkTertiary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(DesignTokens.tierOrange)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click to open Global Core and configure universal tools")
                    } else {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.tierOrange)
                            Text("Global Core:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DesignTokens.ink)
                            Text("Always active across all workspaces")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.inkTertiary)
                        }
                    }

                    Text("•")
                        .foregroundStyle(DesignTokens.inkTertiary)

                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.secondary)
                        Text("Projects:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DesignTokens.ink)
                        Text("Scoped exclusively to the selected project")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.inkTertiary)
                    }
                    .help("Select an individual project in the sidebar for isolated activation")
                }
                .padding(.top, DesignTokens.Spacing.xxs)
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
