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

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow

            if let summary, !summary.isEmpty {
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
        .padding(16)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.default))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.default)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.cardHoverBorder : DesignTokens.cardBorder,
                    lineWidth: isHovered ? 1.5 : 1.0
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
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(DesignTokens.storeBlueTint)
                    .frame(width: 38, height: 38)
                Image(systemName: iconName)
                    .font(.system(size: 17))
                    .foregroundStyle(DesignTokens.primary)
            }
            .overlay(
                Circle()
                    .strokeBorder(DesignTokens.primary.opacity(0.2), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    badges
                }
            }

            Spacer(minLength: 8)

            actions
        }
    }

    private func commandExecutionBox(cmd: String) -> some View {
        HStack {
            Text(cmd)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignTokens.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

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
                    .foregroundStyle(isCopied ? DesignTokens.primary : DesignTokens.inkTertiary)
            }
            .buttonStyle(.plain)
            .help("Copy CLI command: \(cmd)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 0.5)
        )
    }
}
