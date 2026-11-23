import SwiftUI
import AppKit

public struct ResourceCardView<LeadingBadge: View, Actions: View>: View {
    public let title: String
    public let subtitle: String?
    public let summary: String?
    public let iconName: String
    public let iconGradient: LinearGradient
    public let accentColor: Color?
    public let badges: LeadingBadge
    public let actions: Actions

    @State private var isHovered: Bool = false
    @State private var isCopied: Bool = false

    public init(
        title: String,
        subtitle: String? = nil,
        summary: String? = nil,
        iconName: String,
        iconGradient: LinearGradient = DesignTokens.Gradients.djiEngineering,
        accentColor: Color? = nil,
        @ViewBuilder badges: () -> LeadingBadge,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.iconName = iconName
        self.iconGradient = iconGradient
        self.accentColor = accentColor
        self.badges = badges()
        self.actions = actions()
    }

    private var shouldShowSummary: Bool {
        guard let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return summary != subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            topRow

            if shouldShowSummary, let summary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subtitle, !subtitle.isEmpty {
                commandExecutionBox(cmd: subtitle)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.cardHoverBorder : DesignTokens.cardBorder,
                    lineWidth: isHovered ? 1.25 : 1.0
                )
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 6 : 2, y: isHovered ? 3 : 1)
        .onHover { hovering in
            withAnimation(DesignTokens.snappySpring) {
                isHovered = hovering
            }
        }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignTokens.brandTint)
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 15))
                    .foregroundStyle(DesignTokens.secondary)
            }
            .overlay(
                Circle()
                    .strokeBorder(DesignTokens.secondary.opacity(0.22), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
                    .lineLimit(1)

                WrappingHStackLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                    badges
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
    }

    private func commandExecutionBox(cmd: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(cmd)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignTokens.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd, forType: .string)
                withAnimation(DesignTokens.snappySpring) { isCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(DesignTokens.snappySpring) { isCopied = false }
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(isCopied ? DesignTokens.Colors.statusSuccess : DesignTokens.inkTertiary)
            }
            .buttonStyle(.plain)
            .help("Copy: \(cmd)")
            .accessibilityLabel("Copy \(cmd)")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 6)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 0.5)
        )
    }
}
