import SwiftUI

public struct SearchBarView: View {
    @Binding public var text: String
    public let placeholder: String

    public init(text: Binding<String>, placeholder: String = "Search...") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.inkTertiary)
                .font(.callout)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(DesignTokens.ink)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search query")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    text.isEmpty ? DesignTokens.cardBorder : DesignTokens.primary,
                    lineWidth: text.isEmpty ? DesignTokens.borderStandard : 1.5
                )
        )
    }
}
