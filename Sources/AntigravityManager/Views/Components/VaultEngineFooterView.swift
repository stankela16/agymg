import SwiftUI

public struct VaultEngineFooterView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("VAULT ENGINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
                Spacer()
                Text("MCP OK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignTokens.secondaryContainer.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("~/.gemini/manager-vault/")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignTokens.inkTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                Circle().fill(DesignTokens.secondary).frame(width: 5, height: 5)
                Text("Connected").font(.system(size: 10)).foregroundStyle(DesignTokens.inkSecondary)
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
