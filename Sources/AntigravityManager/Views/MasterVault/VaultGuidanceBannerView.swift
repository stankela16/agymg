import SwiftUI

public struct VaultGuidanceBannerView: View {
    var state: AppState? = nil

    public init(state: AppState? = nil) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignTokens.storeBlueTint)
                    .frame(width: 28, height: 28)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Central catalog in ~/.gemini/manager-vault/")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
                Text("Tools here are inactive until enabled in Global Core (all workspaces) or scoped to an individual Project.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            if let state {
                Button {
                    state.navigationSelection = .globalCore
                } label: {
                    Label("Global Core", systemImage: "globe")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Global Core to configure always-active universal tools")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }
}
