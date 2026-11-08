import SwiftUI
import AppKit

/// Apple HIG compliant logo view for Antigravity Manager.
/// Uses a continuous superellipse rounded rectangle with zero I/O in `body`.
public struct AppLogoView: View {
    public let size: CGFloat
    public let cornerRadius: CGFloat
    public let showBorder: Bool

    // Cache the image statically in memory so zero I/O occurs during SwiftUI body evaluation
    private static let cachedImage: NSImage? = {
        #if SWIFT_PACKAGE
        if let moduleURL = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
           let img = NSImage(contentsOf: moduleURL) {
            return img
        }
        #endif

        if let appResourceURL = Bundle.main.url(forResource: "AppLogo", withExtension: "png"),
           let img = NSImage(contentsOf: appResourceURL) {
            return img
        }

        let directURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppLogo.png")
        if let img = NSImage(contentsOf: directURL) {
            return img
        }

        return nil
    }()

    public init(size: CGFloat = 22, cornerRadius: CGFloat = 5.5, showBorder: Bool = true) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.showBorder = showBorder
    }

    public var body: some View {
        if let nsImage = Self.cachedImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if showBorder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                }
                .shadow(color: Color.black.opacity(0.12), radius: 1.5, x: 0, y: 0.5)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x15382B), Color(hex: 0x0A1F17)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(DesignTokens.primary)
            }
            .frame(width: size, height: size)
            .overlay {
                if showBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                }
            }
        }
    }
}
