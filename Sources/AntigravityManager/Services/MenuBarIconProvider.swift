import SwiftUI
import AppKit

/// Provides the high-resolution branded menu bar icon for Antigravity Manager.
/// Follows Apple HIG standards with zero I/O on re-renders.
@MainActor
public enum MenuBarIconProvider {

    /// Resolves bundled resources safely across packaged `.app` bundles, Homebrew `libexec/agymg.app`,
    /// unpackaged SwiftPM builds, and `swift test` without invoking SwiftPM's trapping resource accessor.
    public static func resourceURL(
        forResource name: String,
        withExtension ext: String,
        appBundleURL: URL? = nil
    ) -> URL? {
        let fm = FileManager.default
        let bundleName = "agymg_AntigravityManager.bundle"

        if let appBundleURL {
            if let appBundle = Bundle(url: appBundleURL),
               let url = appBundle.url(forResource: name, withExtension: ext) {
                return url
            }
            let directFile = appBundleURL.appendingPathComponent("Contents/Resources/\(name).\(ext)")
            if fm.fileExists(atPath: directFile.path) {
                return directFile
            }
            let nestedBundleURL = appBundleURL.appendingPathComponent("Contents/Resources/\(bundleName)")
            if let nestedBundle = Bundle(url: nestedBundleURL),
               let url = nestedBundle.url(forResource: name, withExtension: ext) {
                return url
            }
            return nil
        }

        // 1. Packaged .app main bundle resources
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        let directMainResource = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).\(ext)")
        if fm.fileExists(atPath: directMainResource.path) {
            return directMainResource
        }

        // 2. Embedded or sibling SwiftPM resource bundles (including symlinked CLI invocations)
        var candidateBundleURLs: [URL] = []
        if let resURL = Bundle.main.resourceURL {
            candidateBundleURLs.append(resURL.appendingPathComponent(bundleName))
        }
        candidateBundleURLs.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"))
        candidateBundleURLs.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))

        if let execURL = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let contentsDir = execURL.deletingLastPathComponent().deletingLastPathComponent()
            let execDirectResource = contentsDir.appendingPathComponent("Resources/\(name).\(ext)")
            if fm.fileExists(atPath: execDirectResource.path) {
                return execDirectResource
            }
            candidateBundleURLs.append(contentsDir.appendingPathComponent("Resources/\(bundleName)"))
            candidateBundleURLs.append(execURL.deletingLastPathComponent().appendingPathComponent(bundleName))
        }

        for bundleURL in candidateBundleURLs {
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        // 3. Loaded bundles fallback (e.g. XCTest runner where .xctest sits beside agymg_AntigravityManager.bundle)
        for loadedBundle in Bundle.allBundles {
            if let url = loadedBundle.url(forResource: name, withExtension: ext) {
                return url
            }
            if let resURL = loadedBundle.resourceURL,
               let nested = Bundle(url: resURL.appendingPathComponent(bundleName)),
               let url = nested.url(forResource: name, withExtension: ext) {
                return url
            }
            let siblingURL = loadedBundle.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName)
            if let siblingBundle = Bundle(url: siblingURL),
               let url = siblingBundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        return nil
    }

    public static let icon: NSImage? = {
        let size = NSSize(width: 18, height: 18)

        func prepareTemplate(_ img: NSImage) -> NSImage {
            img.size = size
            img.isTemplate = true
            return img
        }

        let candidates = [
            "MenuBarIconTemplate",
            "MenuBarIconTemplate@2x",
            "MenuBarLogo",
            "MenuBarLogo@2x",
            "AppLogo"
        ]
        for candidate in candidates {
            if let url = resourceURL(forResource: candidate, withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                return prepareTemplate(img)
            }
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
