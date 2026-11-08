import SwiftUI

public struct ResourcePillBadge: View {
    public let title: String
    public let icon: String?
    public let color: Color
    public let backgroundColor: Color
    public let isMonospaced: Bool

    public init(
        title: String,
        icon: String? = nil,
        color: Color = DesignTokens.inkSecondary,
        backgroundColor: Color? = nil,
        isMonospaced: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.backgroundColor = backgroundColor ?? color.opacity(0.12)
        self.isMonospaced = isMonospaced
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(title)
                .font(isMonospaced ? .system(.caption2, design: .monospaced).weight(.semibold) : .caption2.weight(.medium))
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(backgroundColor)
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - Factory Presets
    public static func category(_ name: String) -> ResourcePillBadge {
        ResourcePillBadge(title: name, color: DesignTokens.inkSecondary, backgroundColor: DesignTokens.fog)
    }

    public static var global: ResourcePillBadge {
        ResourcePillBadge(title: "GLOBAL", color: DesignTokens.tierOrange, backgroundColor: DesignTokens.tierOrange.opacity(0.12), isMonospaced: true)
    }

    public static var projectPlugin: ResourcePillBadge {
        ResourcePillBadge(title: "PROJECT", color: DesignTokens.djiBlue, backgroundColor: DesignTokens.storeBlueTint, isMonospaced: true)
    }

    public static var linkedToProject: ResourcePillBadge {
        ResourcePillBadge(title: "LINKED", color: DesignTokens.djiBlue, backgroundColor: DesignTokens.storeBlueTint, isMonospaced: true)
    }

    public static var mcpBundle: ResourcePillBadge {
        ResourcePillBadge(title: "MCP BUNDLE", color: DesignTokens.djiBlue, backgroundColor: DesignTokens.storeBlueTint, isMonospaced: true)
    }

    public static var skillsBundle: ResourcePillBadge {
        ResourcePillBadge(title: "SKILLS", color: DesignTokens.inkSecondary, backgroundColor: DesignTokens.fog, isMonospaced: true)
    }

    public static func counter(_ count: Int, color: Color = DesignTokens.djiBlue) -> ResourcePillBadge {
        ResourcePillBadge(title: "\(count)", color: color, backgroundColor: DesignTokens.storeBlueTint, isMonospaced: true)
    }

    public static func scopedProjects(_ count: Int) -> ResourcePillBadge {
        ResourcePillBadge(
            title: "\(count) \(count == 1 ? "PROJECT" : "PROJECTS")",
            icon: "folder",
            color: DesignTokens.secondary,
            backgroundColor: DesignTokens.secondaryContainer.opacity(0.25),
            isMonospaced: true
        )
    }

    public static var catalogOnly: ResourcePillBadge {
        ResourcePillBadge(
            title: "CATALOG",
            icon: "archivebox",
            color: DesignTokens.inkTertiary,
            backgroundColor: DesignTokens.surfaceContainer,
            isMonospaced: true
        )
    }
}

public struct KeyboardShortcutBadge: View {
    public let shortcut: String

    public init(_ shortcut: String) {
        self.shortcut = shortcut
    }

    public var body: some View {
        Text(shortcut)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.surfaceContainerLowest)
            .foregroundStyle(DesignTokens.ink)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs)
                    .strokeBorder(DesignTokens.cardBorder, lineWidth: 1.0)
            )
            .help("Keyboard shortcut: \(shortcut)")
    }
}
