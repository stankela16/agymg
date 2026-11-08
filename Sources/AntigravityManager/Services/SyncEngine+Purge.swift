import Foundation

public struct UninstallRestoreSummary: Codable, Sendable {
    public var restoredGlobalSkills: [String]
    public var restoredGlobalPlugins: [String]
    public var removedProjectWrappers: [String]
    public var removedProjectSymlinks: [String]
    public var removedHelperScript: Bool
    public var cleanedClaudeConfigs: [String]
    public var cleanedClaudeHooks: Bool
    public var purgedVault: Bool
    public var vaultPath: String

    public init(
        restoredGlobalSkills: [String] = [],
        restoredGlobalPlugins: [String] = [],
        removedProjectWrappers: [String] = [],
        removedProjectSymlinks: [String] = [],
        removedHelperScript: Bool = false,
        cleanedClaudeConfigs: [String] = [],
        cleanedClaudeHooks: Bool = false,
        purgedVault: Bool = false,
        vaultPath: String
    ) {
        self.restoredGlobalSkills = restoredGlobalSkills
        self.restoredGlobalPlugins = restoredGlobalPlugins
        self.removedProjectWrappers = removedProjectWrappers
        self.removedProjectSymlinks = removedProjectSymlinks
        self.removedHelperScript = removedHelperScript
        self.cleanedClaudeConfigs = cleanedClaudeConfigs
        self.cleanedClaudeHooks = cleanedClaudeHooks
        self.purgedVault = purgedVault
        self.vaultPath = vaultPath
    }
}

extension SyncEngine {
    // MARK: - Permanent Deletion / Purge
    public func purgeServerCompletely(id: String, allProjects: [ProjectProfile]) throws {
        guard PathConstants.isSafeResourceId(id) else { return }

        let globalFile = PathConstants.globalMCPConfigFile
        let canonicalGlobalFile = globalFile.resolvingSymlinksInPath()
        if let data = try? Data(contentsOf: canonicalGlobalFile),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var servers = json["mcpServers"] as? [String: Any] {
            servers.removeValue(forKey: id)
            json["mcpServers"] = servers
            let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try PathConstants.writeSecureData(updatedData, to: canonicalGlobalFile, permissions: 0o600)
        }

        let fm = FileManager.default
        for project in allProjects {
            let mcpFile = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins/agy-manager/mcp_config.json")
            if let data = try? Data(contentsOf: mcpFile),
               var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               var servers = json["mcpServers"] as? [String: Any] {
                servers.removeValue(forKey: id)
                if servers.isEmpty {
                    let pluginDir = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins/agy-manager")
                    try? fm.removeItem(at: pluginDir)
                } else {
                    json["mcpServers"] = servers
                    let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    try PathConstants.writeSecureData(updatedData, to: mcpFile, permissions: 0o600)
                }
            }
        }

        // Purge from Claude ~/.claude.json across primary home and all AntigravityProfiles (never deleting ~/.local/share directories)
        for configFile in PathConstants.allClaudeConfigFiles {
            let claudeConfigURL = configFile.resolvingSymlinksInPath()
            if let data = try? Data(contentsOf: claudeConfigURL),
               var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var changed = false
                if var globalServers = json["mcpServers"] as? [String: Any],
                   globalServers.removeValue(forKey: id) != nil {
                    json["mcpServers"] = globalServers
                    changed = true
                }
                if var projectsDict = json["projects"] as? [String: Any] {
                    for project in allProjects {
                        if var projEntry = projectsDict[project.path] as? [String: Any],
                           var projServers = projEntry["mcpServers"] as? [String: Any],
                           projServers.removeValue(forKey: id) != nil {
                            projEntry["mcpServers"] = projServers
                            projectsDict[project.path] = projEntry
                            changed = true
                        }
                    }
                    if changed {
                        json["projects"] = projectsDict
                    }
                }
                if changed,
                   let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                    try? PathConstants.writeSecureData(updatedData, to: claudeConfigURL, permissions: 0o600, preserveExistingPermissions: true)
                }
            }
        }
    }

    public func purgeSkillCompletely(id: String, allProjects: [ProjectProfile]) {
        guard PathConstants.isSafeResourceId(id) else { return }
        let fm = FileManager.default

        let globalSkillURL = PathConstants.globalSkillsDirectory.appendingPathComponent(id)
        if isSymlink(at: globalSkillURL) {
            try? fm.removeItem(at: globalSkillURL)
        }

        let claudeGlobalSkillURL = PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent(id)
        if isSymlink(at: claudeGlobalSkillURL) {
            try? fm.removeItem(at: claudeGlobalSkillURL)
        }

        for project in allProjects {
            let projectSkillURL = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/skills/\(id)")
            if isSymlink(at: projectSkillURL) {
                try? fm.removeItem(at: projectSkillURL)
            }
            let claudeProjectSkillURL = URL(fileURLWithPath: project.path).appendingPathComponent(".claude/skills/\(id)")
            if isSymlink(at: claudeProjectSkillURL) {
                try? fm.removeItem(at: claudeProjectSkillURL)
            }
        }
    }

    public func purgePluginCompletely(id: String, allProjects: [ProjectProfile]) {
        guard PathConstants.isSafeResourceId(id), id != "agy-manager" else { return }
        let fm = FileManager.default

        let globalPluginURL = PathConstants.globalPluginsDirectory.appendingPathComponent(id)
        if isSymlink(at: globalPluginURL) {
            try? fm.removeItem(at: globalPluginURL)
        }

        let vaultPluginPrefix = PathConstants.vaultPluginsDirectory
            .appendingPathComponent(id, isDirectory: true)
            .standardizedFileURL.path + "/"

        if let items = try? fm.contentsOfDirectory(at: PathConstants.claudeGlobalSkillsDirectory, includingPropertiesForKeys: nil) {
            for item in items where isSymlink(at: item) {
                if let dest = try? fm.destinationOfSymbolicLink(atPath: item.path) {
                    let absDest = URL(fileURLWithPath: dest, relativeTo: item.deletingLastPathComponent()).standardizedFileURL.path
                    if absDest.hasPrefix(vaultPluginPrefix) {
                        try? fm.removeItem(at: item)
                    }
                }
            }
        }

        for project in allProjects {
            let projectPluginURL = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins/\(id)")
            if isSymlink(at: projectPluginURL) {
                try? fm.removeItem(at: projectPluginURL)
            }

            let claudeProjSkills = URL(fileURLWithPath: project.path).appendingPathComponent(".claude/skills", isDirectory: true)
            if let items = try? fm.contentsOfDirectory(at: claudeProjSkills, includingPropertiesForKeys: nil) {
                for item in items where isSymlink(at: item) {
                    if let dest = try? fm.destinationOfSymbolicLink(atPath: item.path) {
                        let absDest = URL(fileURLWithPath: dest, relativeTo: item.deletingLastPathComponent()).standardizedFileURL.path
                        if absDest.hasPrefix(vaultPluginPrefix) {
                            try? fm.removeItem(at: item)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Uninstall & Restore
    public func uninstallAndRestore(
        projects: [ProjectProfile],
        purgeVault: Bool = false
    ) throws -> UninstallRestoreSummary {
        let fm = FileManager.default
        let vaultDir = PathConstants.vaultDirectory
        let vaultStdPath = vaultDir.standardizedFileURL.path

        func resolveEvenIfMissing(_ url: URL) -> String {
            let std = url.standardizedFileURL
            if fm.fileExists(atPath: std.path) {
                return std.resolvingSymlinksInPath().path
            }
            let parent = std.deletingLastPathComponent()
            let leaf = std.lastPathComponent
            if parent.path == std.path || leaf.isEmpty {
                return std.path
            }
            return URL(fileURLWithPath: resolveEvenIfMissing(parent))
                .appendingPathComponent(leaf)
                .standardizedFileURL.path
        }

        let vaultResolvedPath = resolveEvenIfMissing(vaultDir)
        let vaultSkillsStdPath = PathConstants.vaultSkillsDirectory.standardizedFileURL.path
        let vaultSkillsResolvedPath = resolveEvenIfMissing(PathConstants.vaultSkillsDirectory)

        var summary = UninstallRestoreSummary(vaultPath: vaultDir.path)

        func vaultDestination(for symlinkURL: URL) -> URL? {
            guard isSymlink(at: symlinkURL),
                  let rawDest = try? fm.destinationOfSymbolicLink(atPath: symlinkURL.path) else {
                return nil
            }
            let absDest = URL(fileURLWithPath: rawDest, relativeTo: symlinkURL.deletingLastPathComponent()).standardizedFileURL
            let resolvedDestPath = resolveEvenIfMissing(absDest)
            if absDest.path == vaultStdPath
                || absDest.path.hasPrefix(vaultStdPath + "/")
                || resolvedDestPath == vaultResolvedPath
                || resolvedDestPath.hasPrefix(vaultResolvedPath + "/") {
                return URL(fileURLWithPath: resolvedDestPath)
            }
            return nil
        }

        // 1. Restore global skills in ~/.gemini/config/skills and ~/.claude/skills back to standalone directories
        for skillsDir in [PathConstants.globalSkillsDirectory, PathConstants.claudeGlobalSkillsDirectory] {
            guard let items = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                guard let vaultTarget = vaultDestination(for: item) else { continue }
                let parentStd = vaultTarget.deletingLastPathComponent().standardizedFileURL.path
                let parentResolved = resolveEvenIfMissing(vaultTarget.deletingLastPathComponent())
                let isTopLevelVaultSkill = (parentStd == vaultSkillsStdPath || parentResolved == vaultSkillsResolvedPath)

                if isTopLevelVaultSkill && fm.fileExists(atPath: vaultTarget.path) {
                    let stagingURL = skillsDir.appendingPathComponent(".agymg_restore_\(UUID().uuidString)")
                    do {
                        try fm.copyItem(at: vaultTarget, to: stagingURL)
                        try fm.removeItem(at: item)
                        try fm.moveItem(at: stagingURL, to: item)
                        summary.restoredGlobalSkills.append(item.path)
                    } catch {
                        try? fm.removeItem(at: stagingURL)
                    }
                } else {
                    try? fm.removeItem(at: item)
                }
            }
        }

        // 2. Restore global plugins in ~/.gemini/config/plugins back to standalone directories
        let globalPluginsDir = PathConstants.globalPluginsDirectory
        if let pluginItems = try? fm.contentsOfDirectory(at: globalPluginsDir, includingPropertiesForKeys: nil) {
            for item in pluginItems {
                guard let vaultTarget = vaultDestination(for: item) else { continue }
                if fm.fileExists(atPath: vaultTarget.path) {
                    let stagingURL = globalPluginsDir.appendingPathComponent(".agymg_restore_\(UUID().uuidString)")
                    do {
                        try fm.copyItem(at: vaultTarget, to: stagingURL)
                        try fm.removeItem(at: item)
                        try fm.moveItem(at: stagingURL, to: item)
                        summary.restoredGlobalPlugins.append(item.path)
                    } catch {
                        try? fm.removeItem(at: stagingURL)
                    }
                } else {
                    try? fm.removeItem(at: item)
                }
            }
        }

        // 3. Gather registered project paths (plus any non-TCC project keys from ~/.claude.json)
        var projectPaths: [String] = []
        var seenPaths: Set<String> = []
        for proj in projects {
            let std = URL(fileURLWithPath: proj.path).standardizedFileURL.path
            if seenPaths.insert(std).inserted {
                projectPaths.append(proj.path)
            }
        }
        for configFile in PathConstants.allClaudeConfigFiles {
            if let data = try? Data(contentsOf: configFile.resolvingSymlinksInPath()),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let claudeProjects = json["projects"] as? [String: Any] {
                for rawPath in claudeProjects.keys where !PathConstants.isTCCProtectedPath(rawPath) {
                    let std = URL(fileURLWithPath: rawPath).standardizedFileURL.path
                    if seenPaths.insert(std).inserted {
                        projectPaths.append(rawPath)
                    }
                }
            }
        }

        // 4. Remove per-project agy-manager wrappers and Vault symlinks
        for projPath in projectPaths {
            let projURL = URL(fileURLWithPath: projPath)
            guard fm.fileExists(atPath: projURL.path) else { continue }

            let wrapperDir = projURL.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
            if fm.fileExists(atPath: wrapperDir.path) || isSymlink(at: wrapperDir) {
                if (try? fm.removeItem(at: wrapperDir)) != nil {
                    summary.removedProjectWrappers.append(wrapperDir.path)
                }
            }

            var removedExcludeEntries: Set<String> = []
            for relDir in [".agents/skills", ".claude/skills", ".agents/plugins"] {
                let targetDir = projURL.appendingPathComponent(relDir, isDirectory: true)
                guard let entries = try? fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: nil) else { continue }
                for entry in entries where vaultDestination(for: entry) != nil {
                    if (try? fm.removeItem(at: entry)) != nil {
                        summary.removedProjectSymlinks.append(entry.path)
                        removedExcludeEntries.insert("\(relDir)/\(entry.lastPathComponent)")
                    }
                }
            }

            if !removedExcludeEntries.isEmpty {
                let excludeURL = projURL.appendingPathComponent(".git/info/exclude")
                if let content = try? String(contentsOf: excludeURL, encoding: .utf8) {
                    let filtered = content
                        .components(separatedBy: .newlines)
                        .filter { !removedExcludeEntries.contains($0.trimmingCharacters(in: .whitespaces)) }
                        .joined(separator: "\n")
                    try? filtered.write(to: excludeURL, atomically: true, encoding: .utf8)
                }
            }
        }

        // 5. Remove Claude OAuth helper script and strip its headersHelper references from ~/.claude.json
        let helperScript = PathConstants.claudeMCPOAuthHelperScript
        let helperPath = helperScript.path
        let helperResolvedPath = resolveEvenIfMissing(helperScript)
        if fm.fileExists(atPath: helperPath) || isSymlink(at: helperScript) {
            if (try? fm.removeItem(at: helperScript)) != nil {
                summary.removedHelperScript = true
            }
        }

        func stripHelperReference(in servers: inout [String: Any]) -> Bool {
            var modified = false
            for (serverId, rawVal) in servers {
                guard var serverDict = rawVal as? [String: Any] else { continue }
                if let ref = serverDict["headersHelper"] as? String,
                   (ref == helperPath || ref == helperResolvedPath) {
                    serverDict.removeValue(forKey: "headersHelper")
                    servers[serverId] = serverDict
                    modified = true
                }
            }
            return modified
        }

        for configFile in PathConstants.allClaudeConfigFiles {
            let claudeConfigURL = configFile.resolvingSymlinksInPath()
            guard let data = try? Data(contentsOf: claudeConfigURL),
                  var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            var changed = false
            if var globalServers = root["mcpServers"] as? [String: Any],
               stripHelperReference(in: &globalServers) {
                root["mcpServers"] = globalServers
                changed = true
            }
            if var projectsDict = root["projects"] as? [String: Any] {
                for (projKey, rawEntry) in projectsDict {
                    guard var projEntry = rawEntry as? [String: Any],
                          var projServers = projEntry["mcpServers"] as? [String: Any],
                          stripHelperReference(in: &projServers) else {
                        continue
                    }
                    projEntry["mcpServers"] = projServers
                    projectsDict[projKey] = projEntry
                    changed = true
                }
                if changed {
                    root["projects"] = projectsDict
                }
            }
            if changed,
               let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                if (try? PathConstants.writeSecureData(updatedData, to: claudeConfigURL, permissions: 0o600, preserveExistingPermissions: true)) != nil {
                    summary.cleanedClaudeConfigs.append(claudeConfigURL.path)
                }
            }
        }

        // 6. Clean agymg SessionStart hook entries from Claude & Antigravity settings.json files if present
        var candidateSettingsFiles: [URL] = [
            PathConstants.claudeSettingsFile,
            PathConstants.geminiSettingsFile,
            PathConstants.globalConfigSettingsFile
        ]
        for profHome in PathConstants.antigravityProfileHomes {
            let profClaudeDir = profHome.appendingPathComponent(".claude", isDirectory: true)
            if !isSymlink(at: profClaudeDir) {
                candidateSettingsFiles.append(profClaudeDir.appendingPathComponent("settings.json"))
            }
        }

        var seenSettingsPaths: Set<String> = []
        for candidate in candidateSettingsFiles {
            let settingsFile = candidate.resolvingSymlinksInPath()
            guard seenSettingsPaths.insert(settingsFile.path).inserted,
                  let settingsData = try? Data(contentsOf: settingsFile),
                  var settingsRoot = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
                  var hooksDict = settingsRoot["hooks"] as? [String: Any],
                  let sessionStartList = hooksDict["SessionStart"] as? [[String: Any]] else {
                continue
            }
            var hooksModified = false
            var filteredGroups: [[String: Any]] = []
            for var group in sessionStartList {
                if let innerHooks = group["hooks"] as? [[String: Any]] {
                    let kept = innerHooks.filter { hook in
                        let cmd = (hook["command"] as? String) ?? ""
                        return !cmd.contains("hook-session-start")
                    }
                    if kept.count != innerHooks.count {
                        hooksModified = true
                    }
                    if !kept.isEmpty {
                        group["hooks"] = kept
                        filteredGroups.append(group)
                    }
                } else {
                    let directCmd = (group["command"] as? String) ?? ""
                    if directCmd.contains("hook-session-start") {
                        hooksModified = true
                    } else {
                        filteredGroups.append(group)
                    }
                }
            }
            if hooksModified {
                if filteredGroups.isEmpty {
                    hooksDict.removeValue(forKey: "SessionStart")
                } else {
                    hooksDict["SessionStart"] = filteredGroups
                }
                if hooksDict.isEmpty {
                    settingsRoot.removeValue(forKey: "hooks")
                } else {
                    settingsRoot["hooks"] = hooksDict
                }
                if let updatedSettings = try? JSONSerialization.data(withJSONObject: settingsRoot, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                    try? PathConstants.writeSecureData(updatedSettings, to: settingsFile, permissions: 0o600, preserveExistingPermissions: true)
                    summary.cleanedClaudeHooks = true
                }
            }
        }

        // 7. Optionally remove ~/.gemini/manager-vault
        if purgeVault && fm.fileExists(atPath: vaultDir.path) {
            try fm.removeItem(at: vaultDir)
            summary.purgedVault = true
        }

        return summary
    }
}
