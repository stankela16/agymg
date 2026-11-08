import SwiftUI

public struct HoverRowModifier: ViewModifier {
    @State private var isHovered: Bool = false
    public let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = DesignTokens.CornerRadius.sm) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? DesignTokens.Colors.hoverBackground : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

public struct CardContainerModifier: ViewModifier {
    public let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = DesignTokens.CornerRadius.md) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(DesignTokens.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
            )
    }
}

public extension View {
    func hoverRow(cornerRadius: CGFloat = DesignTokens.CornerRadius.sm) -> some View {
        modifier(HoverRowModifier(cornerRadius: cornerRadius))
    }

    func cardContainer(cornerRadius: CGFloat = DesignTokens.CornerRadius.md) -> some View {
        modifier(CardContainerModifier(cornerRadius: cornerRadius))
    }
}
