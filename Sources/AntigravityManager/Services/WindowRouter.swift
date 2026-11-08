import Foundation
import AppKit

@MainActor
public enum WindowRouter {
    public static var openControlCenter: (() -> Void)?

    public static func dismissPopover() {
        let app = NSApplication.shared
        for window in app.windows where window.isVisible && (window.level == .statusBar || window.className.contains("MenuBar") || window.className.contains("Popover")) {
            window.orderOut(nil)
        }
    }

    public static func findControlCenterWindow(in app: NSApplication = .shared) -> NSWindow? {
        app.windows.first { window in
            // Must be currently open (either visible on screen or miniaturized in the Dock)
            guard window.isVisible || window.isMiniaturized else { return false }

            // Exclude status bar items, popovers, and menus
            guard window.level != .statusBar,
                  !window.className.contains("MenuBar"),
                  !window.className.contains("Popover") else {
                return false
            }

            // Exclude open/save dialog panels
            if window is NSOpenPanel || window is NSSavePanel {
                return false
            }

            // 1. Primary check: SwiftUI Window Scene Identifier ("control-center")
            if let id = window.identifier?.rawValue, id == "control-center" || id.contains("control-center") {
                return true
            }

            // Exclude standalone Settings / Preferences window (only if NOT control-center)
            if window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" || (window.title == "Settings" && window.identifier?.rawValue != "control-center") {
                return false
            }

            // 2. Secondary check: Default or legacy window titles
            if window.title == "agymg" || window.title.contains("agymg") || window.title.contains("Control Center") {
                return true
            }

            // 3. Tertiary check: Dynamic Navigation Section titles set by ControlCenterView
            let knownNavTitles = [
                "Master Vault",
                "Global Core",
                "Plugins Catalog",
                "System Built-ins",
                "Skill Editor",
                "Sync Engine Logs",
                "Sync Engine Status"
            ]
            if knownNavTitles.contains(where: { window.title.hasPrefix($0) }) {
                return true
            }

            return false
        }
    }

    public static func triggerOpen() {
        dismissPopover()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        if let existing = findControlCenterWindow(in: app) {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
        } else {
            openControlCenter?()
        }
    }
}
