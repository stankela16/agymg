import SwiftUI
import AppKit

extension Color {
    public init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    public static func dynamic(light: UInt, dark: UInt, alpha: Double = 1.0) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: CGFloat(alpha))
        })
    }
}

public enum DesignTokens: Sendable {
    // MARK: - Surfaces & Backgrounds
    public static let background = Color.dynamic(light: 0xF8FAF9, dark: 0x0D1310)
    public static let surface = background
    public static let surfaceContainerLowest = Color.dynamic(light: 0xFFFFFF, dark: 0x141A17)
    public static let surfaceContainerLow = Color.dynamic(light: 0xF2F4F3, dark: 0x1A221F)
    public static let surfaceContainer = Color.dynamic(light: 0xECEEED, dark: 0x1F2824)
    public static let surfaceContainerHigh = Color.dynamic(light: 0xE6E9E8, dark: 0x25312C)
    public static let panel = Color.dynamic(light: 0xF2F4F3, dark: 0x161D19)
    public static let fog = Color.dynamic(light: 0xE1E3E2, dark: 0x26322C)

    // MARK: - Primary Emerald & Mint Core
    public static let primary = Color.dynamic(light: 0x002217, dark: 0x6FFBBE)
    public static let primaryContainer = Color.dynamic(light: 0x15382B, dark: 0x003A26)
    public static let onPrimary = Color.white
    public static let onPrimaryContainer = Color.dynamic(light: 0x7DA291, dark: 0xA9CFBC)

    public static let secondary = Color.dynamic(light: 0x006C49, dark: 0x4EDEA3)
    public static let secondaryContainer = Color.dynamic(light: 0x6CF8BB, dark: 0x005137)
    public static let onSecondaryContainer = Color.dynamic(light: 0x00714D, dark: 0x6FFBBE)
    public static let secondaryFixed = Color.dynamic(light: 0x6FFBBE, dark: 0x005236)
    public static let secondaryFixedDim = Color.dynamic(light: 0x4EDEA3, dark: 0x003A26)

    // Legacy aliases bridged to Stitch palette
    public static let storeBlueTint = Color.dynamic(light: 0xEDFAF3, dark: 0x13271F)
    public static let onSecondaryFixedVariant = Color.dynamic(light: 0x005236, dark: 0x6FFBBE)
    public static let tierOrange = Color.dynamic(light: 0xE58929, dark: 0xF5A047)
    public static let badgeOrange = Color.dynamic(light: 0xFA8C16, dark: 0xDB6D28)

    // MARK: - Inks & Text
    public static let ink = Color.dynamic(light: 0x191C1C, dark: 0xEFF1F0)
    public static let inkSecondary = Color.dynamic(light: 0x414844, dark: 0x9AA59F)
    public static let inkTertiary = Color.dynamic(light: 0x717974, dark: 0x6D7A73)
    public static let slate = Color.dynamic(light: 0x5D6862, dark: 0x8A9690)
    public static let steel = Color.dynamic(light: 0x7A8780, dark: 0x829189)

    // MARK: - Dividers & Borders
    public static let hairline = Color.dynamic(light: 0xECEEED, dark: 0x1F2824)
    public static let divider = Color.dynamic(light: 0xE1E3E2, dark: 0x243029)
    public static let cardBorder = Color.dynamic(light: 0xDCE0DE, dark: 0x27342D)
    public static let cardHoverBorder = Color.dynamic(light: 0x006C49, dark: 0x4EDEA3)
    public static let borderHairline: CGFloat = 0.5
    public static let borderStandard: CGFloat = 1.0
    public static let borderActiveRing: CGFloat = 2.0

    public static let canvas = surfaceContainerLowest, canvasSoft = background
    public static let djiBlue = secondary, storeBlue = secondary
    public static let obsidianBase = background, obsidianSurface = surfaceContainerLowest
    public static let obsidianSurfaceHover = surfaceContainerLow, obsidianElevated = panel, obsidianWell = surfaceContainerLow
    public static let studioPrimary = ink, studioMuted = inkSecondary, studioSubtle = inkTertiary
    public static let neonEmerald = Color(hex: 0x006C49), electricIndigo = primaryContainer, electricViolet = secondary, studioAmber = tierOrange

    public static let cardGradient = LinearGradient(colors: [canvas, canvas], startPoint: .top, endPoint: .bottom)
    public static let cardHoverGradient = LinearGradient(colors: [canvas, panel], startPoint: .top, endPoint: .bottom)
    public static let specularIdle = LinearGradient(colors: [divider, hairline], startPoint: .top, endPoint: .bottom)
    public static let specularHover = LinearGradient(colors: [secondary.opacity(0.3), secondary.opacity(0.1)], startPoint: .top, endPoint: .bottom)
    public static let snappySpring = Animation.spring(response: 0.22, dampingFraction: 0.8)
    public static let smoothSpring = Animation.spring(response: 0.32, dampingFraction: 0.85)

    public enum Spacing: Sendable {
        public static let xxs: CGFloat = 4, xs: CGFloat = 8, sm: CGFloat = 12
        public static let md: CGFloat = 16, lg: CGFloat = 20, xl: CGFloat = 24
        public static let xxl: CGFloat = 32, hero: CGFloat = 48
    }

    public enum CornerRadius: Sendable {
        public static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        public static let `default`: CGFloat = 16, lg: CGFloat = 24, xl: CGFloat = 32
        public static let pill: CGFloat = 9999
    }

    public enum Dimensions: Sendable {
        public static let popoverWidth: CGFloat = 360, popoverMaxHeight: CGFloat = 480
        public static let sidebarMinWidth: CGFloat = 240, sidebarIdealWidth: CGFloat = 280, sidebarMaxWidth: CGFloat = 340
        public static let windowMinWidth: CGFloat = 960, windowMinHeight: CGFloat = 660
        public static let statusDotSize: CGFloat = 7, statusDotLargeSize: CGFloat = 9, iconFrameWidth: CGFloat = 18
    }

    public enum Colors: Sendable {
        public static var windowBackground: Color { DesignTokens.background }
        public static var controlBackground: Color { DesignTokens.panel }
        public static var cardBackground: Color { DesignTokens.surfaceContainerLowest }
        public static var hoverBackground: Color { DesignTokens.surfaceContainerLow }
        public static var cardBorder: Color { DesignTokens.cardBorder }
        public static var cardHoverBorder: Color { DesignTokens.cardHoverBorder }
        public static var cardShadow: Color { Color.black.opacity(0.04) }
        public static var cardHoverShadow: Color { Color.black.opacity(0.08) }
        public static let statusActive = DesignTokens.secondary, statusInactive = DesignTokens.steel
        public static let statusSyncing = DesignTokens.tierOrange, statusProject = DesignTokens.secondary
        public static let statusError = Color(hex: 0xBA1A1A), statusWarning = DesignTokens.tierOrange
        public static let statusActiveBg = DesignTokens.storeBlueTint
        public static let statusInactiveBg = DesignTokens.surfaceContainerHigh
        public static let statusSyncingBg = DesignTokens.tierOrange.opacity(0.12)
        public static let statusProjectBg = DesignTokens.storeBlueTint
        public static let statusErrorBg = Color(hex: 0xBA1A1A).opacity(0.12)
        public static let statusWarningBg = DesignTokens.tierOrange.opacity(0.12)
    }

    public enum Materials: Sendable {
        public static let popoverBackground = Material.regularMaterial
        public static let cardMaterial = Material.regularMaterial
    }

    public enum Gradients: Sendable {
        public static let emeraldAccent = LinearGradient(colors: [Color(hex: 0x006C49), Color(hex: 0x002217)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let mintGlow = LinearGradient(colors: [Color(hex: 0x6CF8BB), Color(hex: 0x4EDEA3)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let forestDark = LinearGradient(colors: [Color(hex: 0x15382B), Color(hex: 0x0A1F17)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let vault = LinearGradient(colors: [Color(hex: 0x1B3529), Color(hex: 0x0D1F17)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let coreTools = emeraldAccent
        public static let djiEngineering = emeraldAccent, appleSwift = emeraldAccent
        public static let videoRemotion = emeraldAccent, multiAgent = emeraldAccent, webFrontend = emeraldAccent

        public static func forCategory(_ category: String) -> LinearGradient {
            let c = category.lowercased()
            if c.contains("vault") || c.contains("security") { return vault }
            if c.contains("plugin") { return forestDark }
            return emeraldAccent
        }

        public static func iconForCategory(_ category: String) -> String {
            let c = category.lowercased()
            if c.contains("database") || c.contains("sql") { return "cylinder.split.1x2" }
            if c.contains("git") || c.contains("source") { return "arrow.triangle.branch" }
            if c.contains("swift") || c.contains("apple") || c.contains("ios") { return "apple.terminal" }
            if c.contains("video") || c.contains("remotion") { return "film" }
            if c.contains("agent") || c.contains("swarm") { return "person.3.sequence" }
            if c.contains("web") || c.contains("ui") { return "safari" }
            if c.contains("cloud") || c.contains("deploy") { return "cloud.fill" }
            return "puzzlepiece.extension"
        }

        public static func projectVisual(for name: String) -> (icon: String, gradient: LinearGradient) {
            let lower = name.lowercased()
            if lower.contains("ios") || lower.contains("mobile") || lower.contains("iphone") { return ("iphone", emeraldAccent) }
            if lower.contains("video") || lower.contains("remotion") || lower.contains("studio") { return ("film", emeraldAccent) }
            if lower.contains("portal") || lower.contains("admin") || lower.contains("auth") { return ("shield.checkered", emeraldAccent) }
            if lower.contains("health") || lower.contains("fitness") { return ("figure.run", emeraldAccent) }
            if lower.contains("api") || lower.contains("server") || lower.contains("backend") { return ("server.rack", emeraldAccent) }
            if lower.contains("cli") || lower.contains("tool") { return ("terminal", emeraldAccent) }
            return ("folder.fill", emeraldAccent)
        }
    }
}
