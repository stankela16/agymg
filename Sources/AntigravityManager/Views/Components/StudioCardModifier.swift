import SwiftUI

// MARK: - DJI Option Card View Modifier
public struct StudioCardModifier: ViewModifier {
    public var isHovered: Bool
    public var cornerRadius: CGFloat
    public var isSelected: Bool

    public init(isHovered: Bool = false, cornerRadius: CGFloat = DesignTokens.CornerRadius.md, isSelected: Bool = false) {
        self.isHovered = isHovered
        self.cornerRadius = cornerRadius
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DesignTokens.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? DesignTokens.storeBlue : (isHovered ? DesignTokens.djiBlue : DesignTokens.cardBorder),
                        lineWidth: isSelected ? DesignTokens.borderActiveRing : DesignTokens.borderStandard
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.06 : 0.02),
                radius: isHovered ? 8 : 2,
                x: 0,
                y: isHovered ? 3 : 1
            )
    }
}

extension View {
    public func studioCard(
        isHovered: Bool = false,
        cornerRadius: CGFloat = DesignTokens.CornerRadius.md,
        ambientGlow: Color? = nil,
        isSelected: Bool = false
    ) -> some View {
        modifier(StudioCardModifier(
            isHovered: isHovered,
            cornerRadius: cornerRadius,
            isSelected: isSelected
        ))
    }

    public func specularBorder(
        isHovered: Bool = false,
        cornerRadius: CGFloat = DesignTokens.CornerRadius.md
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isHovered ? DesignTokens.djiBlue : DesignTokens.cardBorder,
                    lineWidth: DesignTokens.borderStandard
                )
        )
    }
}
