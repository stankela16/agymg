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
    // MARK: - Architectural Neutral Surfaces & Backgrounds (Zero Green Cast)
    public static let background = Color.dynamic(light: 0xF6F7F9, dark: 0x0E1015)
    public static let surface = background
    public static let surfaceContainerLowest = Color.dynamic(light: 0xFFFFFF, dark: 0x151821)
    public static let surfaceContainerLow = Color.dynamic(light: 0xF0F2F6, dark: 0x1B1F2B)
    public static let surfaceContainer = Color.dynamic(light: 0xE8EBF1, dark: 0x222736)
    public static let surfaceContainerHigh = Color.dynamic(light: 0xDDE1EA, dark: 0x2B3144)
    public static let panel = Color.dynamic(light: 0xEFEFF3, dark: 0x12141B)
    public static let fog = Color.dynamic(light: 0xE4E7EF, dark: 0x262B3B)

    // MARK: - Obsidian & Electric Iris Brand Core
    public static let primary = Color.dynamic(light: 0x1A1D2B, dark: 0xE8ECFF)
    public static let primaryContainer = Color.dynamic(light: 0x4F46E5, dark: 0x5B5BF0)
    public static let onPrimary = Color.white
    public static let onPrimaryContainer = Color.dynamic(light: 0xE0E7FF, dark: 0xC7D2FE)

    public static let secondary = Color.dynamic(light: 0x4338CA, dark: 0x818CF8)
    public static let secondaryContainer = Color.dynamic(light: 0xC7D2FE, dark: 0x312E81)
    public static let onSecondaryContainer = Color.dynamic(light: 0x3730A3, dark: 0xA5B4FC)
    public static let secondaryFixed = Color.dynamic(light: 0xC7D2FE, dark: 0x3730A3)
    public static let secondaryFixedDim = Color.dynamic(light: 0xA5B4FC, dark: 0x2E2A72)

    // Brand Tints & Signal Amber Accent
    public static let brandTint = Color.dynamic(light: 0xEEF0FF, dark: 0x1D213B)
    public static let storeBlueTint = brandTint
    public static let onSecondaryFixedVariant = Color.dynamic(light: 0x312E81, dark: 0xC7D2FE)
    public static let tierOrange = Color.dynamic(light: 0xD97706, dark: 0xF5A524)
    public static let badgeOrange = Color.dynamic(light: 0xEA580C, dark: 0xFB923C)

    // MARK: - Inks & Text
    public static let ink = Color.dynamic(light: 0x14171F, dark: 0xF1F3F9)
    public static let inkSecondary = Color.dynamic(light: 0x4B5263, dark: 0x9AA2B5)
    public static let inkTertiary = Color.dynamic(light: 0x767E91, dark: 0x6C7488)
    public static let slate = Color.dynamic(light: 0x5C6478, dark: 0x8B93A8)
    public static let steel = Color.dynamic(light: 0x7A8296, dark: 0x7E869B)

    // MARK: - Dividers & Borders
    public static let hairline = Color.dynamic(light: 0xE6E9F0, dark: 0x1F2433)
    public static let divider = Color.dynamic(light: 0xDDE1EA, dark: 0x262C3D)
    public static let cardBorder = Color.dynamic(light: 0xD5DAE6, dark: 0x2C3347)
    public static let cardHoverBorder = Color.dynamic(light: 0x4F46E5, dark: 0x818CF8)
    public static let borderHairline: CGFloat = 0.5
    public static let borderStandard: CGFloat = 1.0
    public static let borderActiveRing: CGFloat = 2.0

    public static let canvas = surfaceContainerLowest, canvasSoft = background
    public static let djiBlue = secondary, storeBlue = secondary
    public static let obsidianBase = background, obsidianSurface = surfaceContainerLowest
    public static let obsidianSurfaceHover = surfaceContainerLow, obsidianElevated = panel, obsidianWell = surfaceContainerLow
    public static let studioPrimary = ink, studioMuted = inkSecondary, studioSubtle = inkTertiary
    public static let neonEmerald = Color.dynamic(light: 0x4338CA, dark: 0x818CF8), electricIndigo = primaryContainer, electricViolet = secondary, studioAmber = tierOrange

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
        public static let statusSuccess = Color.dynamic(light: 0x10915D, dark: 0x34D399)
        public static let statusSuccessBg = Color.dynamic(light: 0xECFDF5, dark: 0x112B22)
        public static let statusSyncing = DesignTokens.tierOrange, statusProject = DesignTokens.secondary
        public static let statusError = Color.dynamic(light: 0xDC2626, dark: 0xF87171), statusWarning = DesignTokens.tierOrange
        public static let statusActiveBg = DesignTokens.brandTint
        public static let statusInactiveBg = DesignTokens.surfaceContainerHigh
        public static let statusSyncingBg = DesignTokens.tierOrange.opacity(0.12)
        public static let statusProjectBg = DesignTokens.brandTint
        public static let statusErrorBg = Color.dynamic(light: 0xFEF2F2, dark: 0x2F171A)
        public static let statusWarningBg = DesignTokens.tierOrange.opacity(0.12)
        public static let accentViolet = Color.dynamic(light: 0x7C3AED, dark: 0xA78BFA)
        public static let accentVioletBg = Color.dynamic(light: 0xF3E8FF, dark: 0x261B3E)
        public static let codeBackground = Color.dynamic(light: 0x11131C, dark: 0x0B0D13)
        public static let codeBorder = Color.dynamic(light: 0x262B3D, dark: 0x222738)
        public static let codeText = Color(hex: 0xA5B4FC)
    }

    public enum Materials: Sendable {
        public static let popoverBackground = Material.regularMaterial
        public static let cardMaterial = Material.regularMaterial
    }

    public enum Gradients: Sendable {
        public static let brandAccent = LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x312E81)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let irisGlow = LinearGradient(colors: [Color(hex: 0x818CF8), Color(hex: 0x4F46E5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let obsidianDark = LinearGradient(colors: [Color(hex: 0x1E2235), Color(hex: 0x10131E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let emeraldAccent = brandAccent
        public static let mintGlow = irisGlow
        public static let forestDark = obsidianDark
        public static let vault = LinearGradient(colors: [Color(hex: 0x242842), Color(hex: 0x121524)], startPoint: .topLeading, endPoint: .bottomTrailing)
        public static let coreTools = brandAccent
        public static let djiEngineering = brandAccent, appleSwift = brandAccent
        public static let videoRemotion = brandAccent, multiAgent = brandAccent, webFrontend = brandAccent

        public static func forCategory(_ category: String) -> LinearGradient {
            let c = category.lowercased()
            if c.contains("vault") || c.contains("security") { return vault }
            if c.contains("plugin") { return obsidianDark }
            return brandAccent
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
