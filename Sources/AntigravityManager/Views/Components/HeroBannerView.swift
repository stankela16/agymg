import SwiftUI
import AppKit

public struct HeroBannerStatItem: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    public let icon: String
    public let tint: Color
    public let subtitle: String

    public init(id: String = UUID().uuidString, label: String, value: String, icon: String, tint: Color = DesignTokens.primary, subtitle: String = "Engine") {
        self.id = id
        self.label = label
        self.value = value
        self.icon = icon
        self.tint = tint
        self.subtitle = subtitle
    }
}

public struct HeroBannerView: View {
    public let title: String
    public let subtitle: String?
    public let tagText: String?
    public let iconName: String
    public let iconGradient: LinearGradient
    public let revealPath: String?
    public let stats: [HeroBannerStatItem]

    @State private var isPathCopied = false

    public init(
        title: String,
        subtitle: String? = nil,
        tagText: String? = nil,
        iconName: String = "folder.fill",
        iconGradient: LinearGradient = DesignTokens.Gradients.djiEngineering,
        revealPath: String? = nil,
        stats: [HeroBannerStatItem] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tagText = tagText
        self.iconName = iconName
        self.iconGradient = iconGradient
        self.revealPath = revealPath
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            topIdentityStrip
            if !stats.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: DesignTokens.Spacing.md)],
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(stats) { telemetryCard(item: $0) }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Spacing.xl)
    }

    private var topIdentityStrip: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("WORKSPACE CLUSTER").font(.system(size: 10, weight: .bold)).foregroundStyle(DesignTokens.tierOrange)
                Text("•").foregroundStyle(DesignTokens.inkTertiary)
                Text("NODE DAEMON #4029").font(.system(size: 11)).foregroundStyle(DesignTokens.inkTertiary)
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(title).font(.system(size: 30, weight: .semibold)).foregroundStyle(DesignTokens.ink)
                HStack(spacing: 5) {
                    Circle().fill(DesignTokens.primary).frame(width: 7, height: 7)
                    Text("ONLINE").font(.system(size: 11, weight: .bold)).foregroundStyle(DesignTokens.primary)
                }
                .padding(.horizontal, 9).padding(.vertical, 4).background(DesignTokens.storeBlueTint).clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.primary.opacity(0.25), lineWidth: 0.5))

                Text("v\(CLIRunner.currentVersion)").font(.system(size: 11, weight: .medium)).foregroundStyle(DesignTokens.inkSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(DesignTokens.surfaceContainerLowest).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(DesignTokens.cardBorder, lineWidth: 0.5))

                if let revealPath { pathPill(path: revealPath) }
                Spacer()
            }
        }
    }

    private func pathPill(path: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(DesignTokens.inkTertiary)
            Text(path).font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.inkSecondary).lineLimit(1).truncationMode(.middle)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
                withAnimation(DesignTokens.snappySpring) { isPathCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(DesignTokens.snappySpring) { isPathCopied = false }
                }
            } label: {
                Image(systemName: isPathCopied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                    .foregroundStyle(isPathCopied ? DesignTokens.primary : DesignTokens.inkTertiary)
            }
            .buttonStyle(.plain).help("Copy directory path")
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private func telemetryCard(item: HeroBannerStatItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(DesignTokens.inkTertiary)
                Spacer()
                Image(systemName: item.icon).font(.system(size: 14)).foregroundStyle(DesignTokens.primary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(item.value).font(.system(size: 18, weight: .semibold)).foregroundStyle(DesignTokens.ink)
                Spacer()
                Text("Ready").font(.system(size: 10, weight: .semibold)).foregroundStyle(DesignTokens.inkSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(DesignTokens.surfaceContainerHigh).clipShape(Capsule())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.surfaceContainerHigh)
                    Capsule().fill(DesignTokens.primaryContainer).frame(width: geo.size.width * 0.85)
                }
            }
            .frame(height: 4)
            HStack(spacing: 4) {
                Circle().fill(DesignTokens.primary).frame(width: 5, height: 5)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(DesignTokens.inkTertiary).lineLimit(1)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.default))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.default)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
    }
}
