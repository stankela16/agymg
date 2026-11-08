import Foundation
import AppKit

@MainActor
public final class ActiveWorkspaceMonitor {
    private weak var appState: AppState?
    private nonisolated(unsafe) var distributedObserver: NSObjectProtocol?
    private nonisolated(unsafe) var workspaceObserver: NSObjectProtocol?

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    public func start(with state: AppState) {
        self.appState = state
        guard !PathConstants.isRunningUnderTests else { return }
        stop()

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: PathConstants.contextDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let path = notification.userInfo?["projectPath"] as? String
            let source = (notification.userInfo?["source"] as? String) ?? "cli"
            let didMutate = (notification.userInfo?["didMutateVault"] as? String) == "true"

            Task { @MainActor [weak self] in
                await self?.handleDistributedSignal(projectPath: path, source: source, didMutateVault: didMutate)
            }
        }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier?.lowercased() ?? ""
            let appName = app?.localizedName?.lowercased() ?? ""

            guard Self.isRelevantIDE(bundleId: bundleId, appName: appName) else { return }
            Task { @MainActor [weak self] in
                await self?.checkIDefocusWorkspace(bundleId: bundleId, appName: appName)
            }
        }
    }

    nonisolated public static func isRelevantIDE(bundleId: String, appName: String) -> Bool {
        let lowerBundle = bundleId.lowercased()
        let lowerName = appName.lowercased()
        if lowerBundle.contains("agymg")
            || lowerBundle.contains("antigravity.manager")
            || lowerBundle.contains("antigravity-monitor")
            || lowerName.contains("antigravity monitor")
            || lowerName == "agymg" {
            return false
        }
        return lowerBundle.contains("antigravity")
            || lowerBundle.contains("cursor")
            || lowerBundle.contains("vscode")
            || lowerBundle.contains("com.microsoft.vscode")
            || lowerBundle.contains("todesktop")
            || lowerName.contains("antigravity")
            || lowerName.contains("cursor")
            || lowerName.contains("visual studio code")
    }

    public func stop() {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    deinit {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    public func handleDistributedSignal(projectPath: String?, source: String, didMutateVault: Bool) async {
        guard let state = appState else { return }
        if didMutateVault {
            await state.reloadFromVaultAfterCLI(preferredProjectPath: projectPath, source: source)
            return
        }

        if let projectPath, !projectPath.isEmpty {
            _ = state.applyDetectedWorkspace(path: projectPath, source: source)
            return
        }

        if let ctx = await state.vaultService.loadActiveContext() {
            _ = state.applyDetectedWorkspace(path: ctx.projectPath, source: ctx.source)
        }
    }

    public func checkIDefocusWorkspace(bundleId: String? = nil, appName: String? = nil) async {
        guard let state = appState, state.autoFollowWorkspace else { return }

        var targetBundleId = bundleId
        var targetAppName = appName
        if targetBundleId == nil && !PathConstants.isRunningUnderTests {
            if let frontmost = NSWorkspace.shared.frontmostApplication {
                let bId = frontmost.bundleIdentifier?.lowercased() ?? ""
                let aName = frontmost.localizedName?.lowercased() ?? ""
                if Self.isRelevantIDE(bundleId: bId, appName: aName) {
                    targetBundleId = bId
                    targetAppName = aName
                }
            }
        }

        let bIdCopy = targetBundleId
        let aNameCopy = targetAppName
        let detected = await Task.detached(priority: .utility) { () -> (path: String, source: String)? in
            if let bIdCopy, !bIdCopy.isEmpty,
               let specific = Self.detectWorkspaceForApp(bundleId: bIdCopy, appName: aNameCopy ?? "") {
                return specific
            }
            return Self.detectMostRecentWorkspaceOnDisk()
        }.value

        if let detected {
            _ = state.applyDetectedWorkspace(path: detected.path, source: detected.source)
        }
    }

    nonisolated public static func detectWorkspaceForApp(
        bundleId: String,
        appName: String,
        home: URL = PathConstants.effectiveHomeDirectory
    ) -> (path: String, source: String)? {
        let fm = FileManager.default
        let lowerBundle = bundleId.lowercased()
        let lowerName = appName.lowercased()

        // 1. Specific IDE with storage.json (Antigravity IDE, Cursor, VS Code)
        var targetedStorageFiles: [URL] = []
        let profilesRoot = home.appendingPathComponent("AntigravityProfiles", isDirectory: true)
        let profileDirs = (try? fm.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.lastPathComponent.hasPrefix("Profile") } ?? []

        if lowerBundle.contains("antigravity-ide") || lowerName.contains("antigravity ide") {
            let matchedProfile = profileDirs.first { profDir in
                let num = profDir.lastPathComponent.dropFirst("Profile".count)
                return !num.isEmpty && (lowerBundle.hasSuffix("profile\(num)") || lowerName.hasSuffix(" \(num)"))
            }
            if let profDir = matchedProfile {
                targetedStorageFiles.append(profDir.appendingPathComponent("ide-data/User/globalStorage/storage.json"))
                targetedStorageFiles.append(profDir.appendingPathComponent("data/User/globalStorage/storage.json"))
                targetedStorageFiles.append(profDir.appendingPathComponent("home/Library/Application Support/Antigravity IDE/User/globalStorage/storage.json"))
                targetedStorageFiles.append(profDir.appendingPathComponent("home/Library/Application Support/Antigravity/User/globalStorage/storage.json"))
            } else {
                targetedStorageFiles.append(home.appendingPathComponent("Library/Application Support/Antigravity IDE/User/globalStorage/storage.json"))
                targetedStorageFiles.append(home.appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/storage.json"))
            }
        } else if lowerBundle.contains("cursor") || lowerBundle.contains("todesktop") || lowerName.contains("cursor") {
            targetedStorageFiles.append(home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/storage.json"))
            for profDir in profileDirs {
                targetedStorageFiles.append(profDir.appendingPathComponent("home/Library/Application Support/Cursor/User/globalStorage/storage.json"))
            }
        } else if lowerBundle.contains("vscode") || lowerName.contains("visual studio code") {
            targetedStorageFiles.append(home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json"))
            for profDir in profileDirs {
                targetedStorageFiles.append(profDir.appendingPathComponent("home/Library/Application Support/Code/User/globalStorage/storage.json"))
            }
        } else if lowerBundle.contains("antigravity") || lowerName.contains("antigravity") {
            // Antigravity Agent Hub app -> check active_context.json written by SessionStart hook / CLI
            let activeCtxURL = PathConstants.activeContextFile
            if let data = try? Data(contentsOf: activeCtxURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let ctx = try? decoder.decode(ActiveWorkspaceContext.self, from: data),
                   !ctx.projectPath.isEmpty,
                   fm.fileExists(atPath: ctx.projectPath) {
                    return (ctx.projectPath, ctx.source)
                }
            }
        }

        var candidates: [(path: String, modified: Date)] = []
        for storageURL in targetedStorageFiles where fm.fileExists(atPath: storageURL.path) {
            guard let attrs = try? fm.attributesOfItem(atPath: storageURL.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let data = try? Data(contentsOf: storageURL),
                  let folderPath = extractActiveFolder(fromStorageJSONData: data),
                  fm.fileExists(atPath: folderPath) else {
                continue
            }
            candidates.append((folderPath, modDate))
        }

        if let newest = candidates.max(by: { $0.modified < $1.modified }) {
            return (newest.path, "ide-focus")
        }
        return nil
    }

    nonisolated public static func allCandidateStorageFiles(home: URL = PathConstants.effectiveHomeDirectory) -> [URL] {
        let fm = FileManager.default
        var storageFiles: [URL] = [
            home.appendingPathComponent("Library/Application Support/Antigravity IDE/User/globalStorage/storage.json"),
            home.appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/storage.json"),
            home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/storage.json"),
            home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json")
        ]

        let profilesRoot = home.appendingPathComponent("AntigravityProfiles", isDirectory: true)
        if let profileDirs = try? fm.contentsOfDirectory(at: profilesRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for profDir in profileDirs where profDir.lastPathComponent.hasPrefix("Profile") {
                storageFiles.append(
                    profDir.appendingPathComponent("ide-data/User/globalStorage/storage.json")
                )
                storageFiles.append(
                    profDir.appendingPathComponent("data/User/globalStorage/storage.json")
                )
                storageFiles.append(
                    profDir.appendingPathComponent("home/Library/Application Support/Antigravity IDE/User/globalStorage/storage.json")
                )
                storageFiles.append(
                    profDir.appendingPathComponent("home/Library/Application Support/Antigravity/User/globalStorage/storage.json")
                )
                storageFiles.append(
                    profDir.appendingPathComponent("home/Library/Application Support/Cursor/User/globalStorage/storage.json")
                )
                storageFiles.append(
                    profDir.appendingPathComponent("home/Library/Application Support/Code/User/globalStorage/storage.json")
                )
                storageFiles.append(
                    profDir.appendingPathComponent("appdata/Antigravity/User/globalStorage/storage.json")
                )
            }
        }
        return storageFiles
    }

    nonisolated public static func detectMostRecentWorkspaceOnDisk() -> (path: String, source: String)? {
        let fm = FileManager.default
        let home = PathConstants.effectiveHomeDirectory

        var candidates: [(path: String, modified: Date, source: String)] = []

        // 1. Check active_context.json written by SessionStart hook / CLI
        let activeCtxURL = PathConstants.activeContextFile
        if let attrs = try? fm.attributesOfItem(atPath: activeCtxURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           let data = try? Data(contentsOf: activeCtxURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let ctx = try? decoder.decode(ActiveWorkspaceContext.self, from: data),
               !ctx.projectPath.isEmpty,
               fm.fileExists(atPath: ctx.projectPath) {
                candidates.append((ctx.projectPath, modDate, ctx.source))
            }
        }

        // 2. Check IDE globalStorage/storage.json files across default home and AntigravityProfiles
        for storageURL in allCandidateStorageFiles(home: home) where fm.fileExists(atPath: storageURL.path) {
            guard let attrs = try? fm.attributesOfItem(atPath: storageURL.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let data = try? Data(contentsOf: storageURL),
                  let folderPath = extractActiveFolder(fromStorageJSONData: data),
                  fm.fileExists(atPath: folderPath) else {
                continue
            }
            candidates.append((folderPath, modDate, "ide-focus"))
        }

        guard let newest = candidates.max(by: { $0.modified < $1.modified }) else {
            return nil
        }
        return (newest.path, newest.source)
    }

    nonisolated public static func extractActiveFolder(fromStorageJSONData data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // 1. windowsState.lastActiveWindow.folder
        if let windowsState = json["windowsState"] as? [String: Any] {
            if let lastActive = windowsState["lastActiveWindow"] as? [String: Any],
               let folderURI = lastActive["folder"] as? String,
               let resolved = pathFromFileURI(folderURI) {
                return resolved
            }
            if let openedWindows = windowsState["openedWindows"] as? [[String: Any]],
               let firstOpen = openedWindows.first,
               let folderURI = firstOpen["folder"] as? String,
               let resolved = pathFromFileURI(folderURI) {
                return resolved
            }
        }

        // 2. backupWorkspaces.folders
        if let backupWorkspaces = json["backupWorkspaces"] as? [String: Any],
           let folders = backupWorkspaces["folders"] as? [[String: Any]],
           let firstFolder = folders.first,
           let folderURI = firstFolder["folderUri"] as? String,
           let resolved = pathFromFileURI(folderURI) {
            return resolved
        }

        return nil
    }

    nonisolated public static func pathFromFileURI(_ uriOrPath: String) -> String? {
        let trimmed = uriOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed), url.isFileURL {
                return url.path
            }
            let stripped = String(trimmed.dropFirst("file://".count))
            return stripped.removingPercentEncoding ?? stripped
        }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        return nil
    }
}
