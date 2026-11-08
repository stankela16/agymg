import Foundation
import AppKit

public final class ProjectFolderAccessManager: @unchecked Sendable {
    public static let shared = ProjectFolderAccessManager()

    public static let userDefaultsKey = "hasAuthorizedProjectsFolder"
    public static let bookmarkKey = "projectsFolderBookmark"
    public static let pathKey = "projectsFolderPath"

    private init() {}

    private var defaults: UserDefaults {
        if !PathConstants.isRunningUnderTests && PathConstants.hasEnvironmentOverride {
            let hash = abs(PathConstants.geminiDirectory.path.hashValue)
            return UserDefaults(suiteName: "com.nikolastanojevic.agymg.env.\(hash)") ?? .standard
        }
        return .standard
    }

    private func ensureEnvironmentAutoAuthIfRequested() {
        guard !PathConstants.isRunningUnderTests,
              PathConstants.hasEnvironmentOverride,
              ProcessInfo.processInfo.environment["AGYMG_AUTO_AUTHORIZE_PROJECTS"] == "1",
              defaults.object(forKey: Self.userDefaultsKey) == nil else {
            return
        }
        saveAuthorization(url: PathConstants.defaultProjectsDirectory)
    }

    public var isAuthorized: Bool {
        get {
            ensureEnvironmentAutoAuthIfRequested()
            if let explicit = defaults.object(forKey: Self.userDefaultsKey) as? Bool {
                return explicit
            }
            if hasSavedFolderAuthorization {
                defaults.set(true, forKey: Self.userDefaultsKey)
                return true
            }
            return false
        }
        set {
            defaults.set(newValue, forKey: Self.userDefaultsKey)
        }
    }

    public var hasSavedBookmark: Bool {
        defaults.data(forKey: Self.bookmarkKey) != nil
    }

    public var hasSavedFolderAuthorization: Bool {
        if let resolvedURL = resolveBookmark() {
            let resolved = resolvedURL.resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: resolved.path) {
                return true
            }
        }
        if let savedPath = defaults.string(forKey: Self.pathKey) {
            let url = URL(fileURLWithPath: savedPath, isDirectory: true).resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
        }
        return false
    }

    /// Returns the explicitly authorized root directory URL, or nil if the user skipped folder setup.
    public var authorizedDirectoryURL: URL? {
        ensureEnvironmentAutoAuthIfRequested()
        if let resolvedURL = resolveBookmark() {
            let resolved = resolvedURL.resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }
        if let savedPath = defaults.string(forKey: Self.pathKey) {
            let url = URL(fileURLWithPath: savedPath, isDirectory: true).resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let custom = PathConstants.customProjectsDirectory {
            return custom.resolvingSymlinksInPath()
        }
        if !PathConstants.isRunningUnderTests,
           let envPath = ProcessInfo.processInfo.environment["AGYMG_PROJECTS_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty {
            return URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath, isDirectory: true).resolvingSymlinksInPath()
        }
        return nil
    }

    public var targetDirectoryURL: URL {
        if let authorized = authorizedDirectoryURL {
            return authorized
        }
        return PathConstants.defaultProjectsDirectory.resolvingSymlinksInPath()
    }

    public func saveAuthorization(url: URL) {
        let canonicalURL = url.resolvingSymlinksInPath()
        let bookmark = (try? canonicalURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? canonicalURL.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? canonicalURL.bookmarkData())
        defaults.set(true, forKey: Self.userDefaultsKey)
        if let bookmark {
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        }
        defaults.set(canonicalURL.path, forKey: Self.pathKey)
    }

    public func resetAuthorization() {
        defaults.set(false, forKey: Self.userDefaultsKey)
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.pathKey)
    }

    @MainActor
    public func requestAuthorization(customURL: URL? = nil) async -> (success: Bool, url: URL?) {
        WindowRouter.dismissPopover()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Connect Workspace Folder"
        panel.prompt = "Grant Access"
        panel.message = "Choose your root projects folder (e.g. ~/Projects or ~/Developer) to discover repositories and sync MCP servers and skills."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = customURL ?? targetDirectoryURL

        let response = panel.runModal()
        if response == .OK, let selectedURL = panel.url {
            saveAuthorization(url: selectedURL)
            return (true, selectedURL)
        }
        return (false, nil)
    }

    public func resolveBookmark() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            return nil
        }
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            if isStale {
                saveAuthorization(url: url)
            }
            return url
        }
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            if isStale {
                saveAuthorization(url: url)
            }
            return url
        }
        return nil
    }
}
