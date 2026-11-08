import SwiftUI
import AppKit

/// Provides the high-resolution branded menu bar icon for Antigravity Manager.
/// Follows Apple HIG standards with zero I/O on re-renders.
@MainActor
public enum MenuBarIconProvider {

    public static let icon: NSImage? = {
        let size = NSSize(width: 18, height: 18)

        func prepareTemplate(_ img: NSImage) -> NSImage {
            img.size = size
            img.isTemplate = true
            return img
        }

        // 1. Try MenuBarIconTemplate from Bundle.module (SwiftPM)
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "MenuBarIconTemplate", withExtension: "png") ??
                     Bundle.module.url(forResource: "MenuBarIconTemplate@2x", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return prepareTemplate(img)
        }
        if let url = Bundle.module.url(forResource: "MenuBarLogo", withExtension: "png") ??
                     Bundle.module.url(forResource: "MenuBarLogo@2x", withExtension: "png") ??
                     Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return prepareTemplate(img)
        }
        #endif

        // 2. Try App Bundle Resources
        if let url = Bundle.main.url(forResource: "MenuBarIconTemplate", withExtension: "png") ??
                     Bundle.main.url(forResource: "MenuBarIconTemplate@2x", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return prepareTemplate(img)
        }
        if let url = Bundle.main.url(forResource: "MenuBarLogo", withExtension: "png") ??
                     Bundle.main.url(forResource: "MenuBarLogo@2x", withExtension: "png") ??
                     Bundle.main.url(forResource: "AppLogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return prepareTemplate(img)
        }

        // 3. Try direct Contents/Resources path in .app bundle
        let templateURL2x = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MenuBarIconTemplate@2x.png")
        if let img = NSImage(contentsOf: templateURL2x) {
            return prepareTemplate(img)
        }
        let templateURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MenuBarIconTemplate.png")
        if let img = NSImage(contentsOf: templateURL) {
            return prepareTemplate(img)
        }

        let directURL2x = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MenuBarLogo@2x.png")
        if let img = NSImage(contentsOf: directURL2x) {
            return prepareTemplate(img)
        }

        let directURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppLogo.png")
        if let img = NSImage(contentsOf: directURL) {
            return prepareTemplate(img)
        }

        // Fallback to system symbol
        if let sfImg = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "Antigravity Manager") {
            return prepareTemplate(sfImg)
        }

        return nil
    }()

    public static let badgedIcon: NSImage? = {
        guard let base = icon else { return nil }
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let dotRect = NSRect(x: rect.maxX - 5.0, y: rect.maxY - 5.0, width: 4.5, height: 4.5)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()

    public static func icon(hasRecommendations: Bool) -> NSImage? {
        hasRecommendations ? (badgedIcon ?? icon) : icon
    }
}
