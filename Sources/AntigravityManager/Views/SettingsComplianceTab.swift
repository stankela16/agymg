import SwiftUI

public struct SettingsComplianceTab: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    AppLogoView(size: 36, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("agymg — Antigravity & Claude Code Manager")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DesignTokens.ink)
                        Text("Version 1.0.0 • Native macOS Control Center (MIT License)")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.inkTertiary)
                    }
                    Spacer()
                }

                Divider()

                Text("macOS Architecture & Design Standards")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    complianceRow(
                        title: "Apple HIG Menu Bar (.commands)",
                        desc: "Full macOS menu hierarchy (App, File, Edit, View, Window, Help) with keyboard shortcuts (⌘S, ⌘O, ⌘R, ⌘1–5), ellipses for dialogs, and native checkmarks.",
                        icon: "menubar.rectangle"
                    )
                    complianceRow(
                        title: "HIG Toolbars & Zero-Lag Views",
                        desc: "Declarative SwiftUI views backed by @Observable state with zero disk I/O in body and contextual .help tooltips across interactive controls.",
                        icon: "character.textbox"
                    )
                    complianceRow(
                        title: "Bjango Menu Bar Extra Standards",
                        desc: "18pt monochrome template icon with automatic Light/Dark vibrancy, 8pt spatial grid popover, and native macOS materials.",
                        icon: "square.fill.text.grid.1x2"
                    )
                    complianceRow(
                        title: "Transparent Login Item Management",
                        desc: "Explicit user opt-in Launch at Login via Apple's SMAppService.mainApp API with no hidden background daemons.",
                        icon: "shield.checkered"
                    )
                }

                Spacer()
            }
            .padding(DesignTokens.Spacing.md)
        }
    }

    private func complianceRow(title: String, desc: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DesignTokens.ink)
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkSecondary)
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }
}
