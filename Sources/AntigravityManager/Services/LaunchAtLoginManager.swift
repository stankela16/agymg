import Foundation
import ServiceManagement
import Observation

/// Manages Launch at Login for Antigravity Manager using Apple's modern SMAppService.mainApp API.
/// Fully compliant with Mac App Store Review Guidelines 2.4.5:
/// - Discloses purpose and background behavior to the user.
/// - Requires explicit user opt-in (disabled by default).
/// - Provides full control to enable/disable at any time.
/// - Detects .requiresApproval and links to macOS System Settings.
@MainActor
@Observable
public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    public private(set) var status: SMAppService.Status = .notRegistered
    public var lastErrorMessage: String? = nil

    public init() {
        refresh()
    }

    public func refresh() {
        status = SMAppService.mainApp.status
    }

    public var isEnabled: Bool {
        get {
            status == .enabled
        }
        set {
            lastErrorMessage = nil
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                if status == .notFound || error.localizedDescription.contains("Operation not permitted") {
                    lastErrorMessage = "Apple SMAppService requires the app to be installed in /Applications and code-signed before registering as a Login Item."
                } else {
                    lastErrorMessage = error.localizedDescription
                }
            }
            refresh()
        }
    }

    public var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications")
    }

    public var statusDescription: String {
        switch status {
        case .enabled:
            return "Enabled (Active at login)"
        case .notRegistered:
            return "Disabled"
        case .requiresApproval:
            return "Requires approval in macOS System Settings"
        case .notFound:
            return "Not configured (Requires installation in /Applications)"
        @unknown default:
            return "Unknown status"
        }
    }

    public func openSystemLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
