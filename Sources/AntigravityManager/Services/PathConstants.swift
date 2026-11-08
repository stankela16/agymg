import Foundation
import CryptoKit
import Darwin

public enum PathConstants {
    public static let appVersion = "1.0.1"

    public nonisolated(unsafe) static var customGeminiDirectory: URL? = nil
    public nonisolated(unsafe) static var customProjectsDirectory: URL? = nil

    public static func stableShortHash(_ input: String, length: Int = 8) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(max(1, length)))
    }

    public static func isSafeResourceId(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == id,
              id != ".",
              id != "..",
              !id.contains("/"),
              !id.contains("\\"),
              !id.contains("\0") else {
            return false
        }
        return true
    }

    public static func isTCCProtectedPath(_ path: String) -> Bool {
        guard !isRunningUnderTests && !hasEnvironmentOverride && customProjectsDirectory == nil else {
            return false
        }
        let home = homeDirectory.standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        for folder in ["Desktop", "Documents", "Downloads"] {
            let prefix = "\(home)/\(folder)"
            if standardized == prefix || standardized.hasPrefix("\(prefix)/") {
                return true
            }
        }
        return false
    }

    public static func writeSecureData(
        _ data: Data,
        to url: URL,
        permissions: Int = 0o600,
        preserveExistingPermissions: Bool = false
    ) throws {
        let fm = FileManager.default
        let canonicalURL = url.resolvingSymlinksInPath()
        let parentDir = canonicalURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let targetMode: Int
        if preserveExistingPermissions,
           let attrs = try? fm.attributesOfItem(atPath: canonicalURL.path),
           let existingMode = (attrs[.posixPermissions] as? NSNumber)?.intValue {
            targetMode = existingMode
        } else {
            targetMode = permissions
        }

        let tmpURL = parentDir.appendingPathComponent(".agymg_tmp_\(UUID().uuidString)")
        guard fm.createFile(atPath: tmpURL.path, contents: nil, attributes: [.posixPermissions: targetMode]) else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create temporary file at \(tmpURL.path)"]
            )
        }
        _ = Darwin.chmod(tmpURL.path, mode_t(targetMode))

        do {
            let handle = try FileHandle(forWritingTo: tmpURL)
            do {
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            if Darwin.rename(tmpURL.path, canonicalURL.path) != 0 {
                let errCode = errno
                try? fm.removeItem(at: tmpURL)
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errCode),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to atomically rename temporary file to \(canonicalURL.path)"]
                )
            }
            _ = Darwin.chmod(canonicalURL.path, mode_t(targetMode))
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw error
        }
    }

    public static var isRunningUnderTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: { $0.contains("xctest") || $0.contains("XCTest") })
    }

    private static var testFallbackGeminiDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AntigravityTestAirlock/.gemini", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("manager-vault", isDirectory: true), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("config", isDirectory: true), withIntermediateDirectories: true)
        return dir
    }

    private static var testFallbackProjectsDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AntigravityTestAirlock/Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var homeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var hasEnvironmentOverride: Bool {
        let env = ProcessInfo.processInfo.environment
        if let g = env["AGYMG_GEMINI_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            return true
        }
        if let p = env["AGYMG_PROJECTS_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return true
        }
        return false
    }

    public static var geminiDirectory: URL {
        if let custom = customGeminiDirectory {
            return custom
        }
        if isRunningUnderTests {
            return testFallbackGeminiDirectory
        }
        if let envPath = ProcessInfo.processInfo.environment["AGYMG_GEMINI_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty {
            return URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".gemini", isDirectory: true)
    }

    public static var globalConfigDirectory: URL {
        geminiDirectory.appendingPathComponent("config", isDirectory: true)
    }

    public static var globalMCPConfigFile: URL {
        globalConfigDirectory.appendingPathComponent("mcp_config.json")
    }

    public static var globalProjectsDirectory: URL {
        globalConfigDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    public static var globalSkillsDirectory: URL {
        globalConfigDirectory.appendingPathComponent("skills", isDirectory: true)
    }

    public static var globalPluginsDirectory: URL {
        globalConfigDirectory.appendingPathComponent("plugins", isDirectory: true)
    }

    public static var vaultDirectory: URL {
        geminiDirectory.appendingPathComponent("manager-vault", isDirectory: true)
    }

    public static var vaultBackupsDirectory: URL {
        vaultDirectory.appendingPathComponent("backups", isDirectory: true)
    }

    public static var vaultMCPFile: URL {
        vaultDirectory.appendingPathComponent("master_mcp.json")
    }

    public static var vaultSkillsDirectory: URL {
        vaultDirectory.appendingPathComponent("skills", isDirectory: true)
    }

    public static var vaultPluginsDirectory: URL {
        vaultDirectory.appendingPathComponent("plugins", isDirectory: true)
    }

    public static var vaultProjectsFile: URL {
        vaultDirectory.appendingPathComponent("projects.json")
    }

    public static var vaultGlobalConfigFile: URL {
        vaultDirectory.appendingPathComponent("global_selection.json")
    }

    public static var activeContextFile: URL {
        vaultDirectory.appendingPathComponent("active_context.json")
    }

    public static let contextDidChangeNotification = Notification.Name("com.nikolastanojevic.agymg.contextDidChange")

    public static var defaultProjectsDirectory: URL {
        if let custom = customProjectsDirectory {
            return custom
        }
        if isRunningUnderTests {
            return testFallbackProjectsDirectory
        }
        if let envPath = ProcessInfo.processInfo.environment["AGYMG_PROJECTS_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty {
            return URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return resolveDefaultProjectsDirectory(in: homeDirectory)
    }

    public static func resolveDefaultProjectsDirectory(in home: URL, fileManager: FileManager = .default) -> URL {
        let candidates = ["Desktop/Projects", "Projects", "Developer", "Code", "workspace"]
        for candidate in candidates {
            let dir = home.appendingPathComponent(candidate, isDirectory: true)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return home.appendingPathComponent("Projects", isDirectory: true)
    }

    public static var desktopProjectsDirectory: URL {
        defaultProjectsDirectory
    }

    // MARK: - Level 0 Built-in Engine Paths
    public static var antigravityEngineDirectory: URL {
        geminiDirectory.appendingPathComponent("antigravity", isDirectory: true)
    }

    public static var builtinSkillsDirectory: URL {
        antigravityEngineDirectory.appendingPathComponent("builtin/skills", isDirectory: true)
    }

    public static var engineMCPDirectory: URL {
        antigravityEngineDirectory.appendingPathComponent("mcp", isDirectory: true)
    }

    public static var engineMCPOAuthTokensFile: URL {
        antigravityEngineDirectory.appendingPathComponent("mcp_oauth_tokens.json")
    }

    // MARK: - Claude Integration Paths
    public static var effectiveHomeDirectory: URL {
        let gemini = geminiDirectory
        if gemini.lastPathComponent == ".gemini" {
            return gemini.deletingLastPathComponent()
        }
        return gemini
    }

    public static var claudeDirectory: URL {
        effectiveHomeDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    public static var claudeConfigFile: URL {
        effectiveHomeDirectory.appendingPathComponent(".claude.json")
    }

    public static var antigravityProfileHomes: [URL] {
        guard customGeminiDirectory != nil || !isRunningUnderTests else { return [] }
        let profilesRoot = effectiveHomeDirectory.appendingPathComponent("AntigravityProfiles", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix("Profile") }
            .map { $0.appendingPathComponent("home", isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static var allClaudeConfigFiles: [URL] {
        var files = [claudeConfigFile]
        for profHome in antigravityProfileHomes {
            files.append(profHome.appendingPathComponent(".claude.json"))
        }
        return files
    }

    public static var claudeGlobalSkillsDirectory: URL {
        claudeDirectory.appendingPathComponent("skills", isDirectory: true)
    }

    public static var claudeHooksDirectory: URL {
        claudeDirectory.appendingPathComponent("hooks", isDirectory: true)
    }

    public static var claudeMCPOAuthHelperScript: URL {
        claudeHooksDirectory.appendingPathComponent("mcp-oauth-headers.py")
    }

    public static var claudeSettingsFile: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    public static var allClaudeNeedsAuthCacheFiles: [URL] {
        var files = [claudeDirectory.appendingPathComponent("mcp-needs-auth-cache.json")]
        for profHome in antigravityProfileHomes {
            files.append(profHome.appendingPathComponent(".claude/mcp-needs-auth-cache.json"))
        }
        return files
    }

    public static var claudeGlobalMemoryFile: URL {
        claudeDirectory.appendingPathComponent("CLAUDE.md")
    }

    public static var geminiGlobalMemoryFile: URL {
        geminiDirectory.appendingPathComponent("GEMINI.md")
    }
}
