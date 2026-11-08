import Foundation

public actor SyncEngine {
    private let fm = FileManager.default

    public init() {}

    public func syncAll(
        servers: [MCPServerDefinition],
        globalServerIds: Set<String>,
        skills: [SkillDefinition],
        globalSkillIds: Set<String>,
        plugins: [PluginDefinition],
        globalPluginIds: Set<String>,
        projects: [ProjectProfile]
    ) throws {
        // 1. Sync Global
        try syncGlobalConfig(servers: servers, enabledIds: globalServerIds)
        try syncGlobalSkills(allSkills: skills, enabledSkillIds: globalSkillIds)
        try syncGlobalPlugins(allPlugins: plugins, enabledPluginIds: globalPluginIds)

        // 2. Sync Each Project
        for project in projects {
            try syncProject(project: project, allServers: servers, allSkills: skills, allPlugins: plugins)
        }
    }

    @discardableResult
    public func createConfigSnapshotIfNeeded(force: Bool = false) -> URL? {
        let backupsDir = PathConstants.vaultBackupsDirectory

        if !force {
            if let existing = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil),
               existing.contains(where: { $0.lastPathComponent.hasPrefix("snapshot-") }) {
                return nil
            }
        }

        var sources: [(url: URL, filename: String)] = [
            (PathConstants.globalMCPConfigFile.resolvingSymlinksInPath(), "mcp_config.json"),
            (PathConstants.claudeConfigFile.resolvingSymlinksInPath(), "claude.json"),
            (PathConstants.claudeSettingsFile.resolvingSymlinksInPath(), "claude_settings.json")
        ]

        for profHome in PathConstants.antigravityProfileHomes {
            let profName = profHome.deletingLastPathComponent().lastPathComponent
            let profClaude = profHome.appendingPathComponent(".claude.json").resolvingSymlinksInPath()
            sources.append((profClaude, "\(profName.lowercased())_claude.json"))
        }

        if force {
            sources.append((PathConstants.vaultMCPFile, "vault_master_mcp.json"))
            sources.append((PathConstants.vaultGlobalConfigFile, "vault_global_selection.json"))
            sources.append((PathConstants.vaultProjectsFile, "vault_projects.json"))
        }

        let existingSources = sources.filter { fm.fileExists(atPath: $0.url.path) }
        if !force && existingSources.isEmpty {
            return nil
        }

        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let baseName = "snapshot-\(formatter.string(from: Date()))"

        var counter = 1
        var snapshotDir = backupsDir.appendingPathComponent(String(format: "%@-%03d", baseName, counter), isDirectory: true)
        while fm.fileExists(atPath: snapshotDir.path) {
            counter += 1
            snapshotDir = backupsDir.appendingPathComponent(String(format: "%@-%03d", baseName, counter), isDirectory: true)
        }

        do {
            try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var copiedFiles: [String] = []
        for item in existingSources {
            let dst = snapshotDir.appendingPathComponent(item.filename)
            if (try? fm.copyItem(at: item.url, to: dst)) != nil {
                copiedFiles.append(item.filename)
            }
        }

        let meta: [String: Any] = [
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "trigger": force ? "manual" : "pre-first-sync",
            "files": copiedFiles
        ]
        if let metaData = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? metaData.write(to: snapshotDir.appendingPathComponent("manifest.json"), options: .atomic)
        }

        // Retain up to 10 snapshots (always preserving the initial pre-first-sync backup)
        if let allEntries = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil) {
            let snapshots = allEntries
                .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if snapshots.count > 10 {
                let firstPreSync = snapshots.first { dir in
                    guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return false
                    }
                    return (json["trigger"] as? String) == "pre-first-sync"
                }
                var keepSet = Set<URL>()
                if let firstPreSync {
                    keepSet.insert(firstPreSync)
                    for recent in snapshots.reversed() where keepSet.count < 10 {
                        keepSet.insert(recent)
                    }
                } else {
                    keepSet.formUnion(snapshots.suffix(10))
                }
                for candidate in snapshots where !keepSet.contains(candidate) {
                    try? fm.removeItem(at: candidate)
                }
            }
        }

        return snapshotDir
    }

    // MARK: - Global MCP Sync
    public func syncGlobalConfig(servers: [MCPServerDefinition], enabledIds: Set<String>) throws {
        _ = createConfigSnapshotIfNeeded(force: false)

        let globalConfigDir = PathConstants.globalConfigDirectory
        try fm.createDirectory(at: globalConfigDir, withIntermediateDirectories: true)

        let globalFile = PathConstants.globalMCPConfigFile
        let canonicalGlobalFile = globalFile.resolvingSymlinksInPath()
        try fm.createDirectory(at: canonicalGlobalFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        let backupFile = globalConfigDir.appendingPathComponent("mcp_config.json.bak")
        if fm.fileExists(atPath: canonicalGlobalFile.path) && !fm.fileExists(atPath: backupFile.path) {
            try? fm.copyItem(at: canonicalGlobalFile, to: backupFile)
        }

        var mcpServersDict: [String: [String: Any]] = [:]

        for server in servers {
            var rawDict: [String: Any] = server.config.mapValues { $0.toAny() }
            if enabledIds.contains(server.id) {
                rawDict["disabled"] = false
            } else {
                rawDict["disabled"] = true
            }
            mcpServersDict[server.id] = rawDict
        }

        var rootDict: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: canonicalGlobalFile),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            rootDict = existingJSON
        }

        rootDict["mcpServers"] = mcpServersDict
        let data = try JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: canonicalGlobalFile, options: .atomic)

        syncClaudeGlobalConfig(servers: servers, enabledIds: enabledIds)
    }

    // MARK: - Global Skills Sync
    public func syncGlobalSkills(allSkills: [SkillDefinition], enabledSkillIds: Set<String>) throws {
        let globalSkillsDir = PathConstants.globalSkillsDirectory
        let vaultSkillsDir = PathConstants.vaultSkillsDirectory

        try fm.createDirectory(at: globalSkillsDir, withIntermediateDirectories: true)

        for skill in allSkills {
            let targetURL = globalSkillsDir.appendingPathComponent(skill.id)
            let vaultSkillURL = vaultSkillsDir.appendingPathComponent(skill.id)
            let sourceURL = fm.fileExists(atPath: vaultSkillURL.path)
                ? vaultSkillURL
                : URL(fileURLWithPath: skill.path)

            if enabledSkillIds.contains(skill.id) {
                let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                if let symlinkDest {
                    if symlinkDest != sourceURL.path {
                        try? fm.removeItem(at: targetURL)
                        if fm.fileExists(atPath: sourceURL.path) {
                            try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                        }
                    }
                } else if !fm.fileExists(atPath: targetURL.path) {
                    if fm.fileExists(atPath: sourceURL.path) {
                        try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                    }
                }
            } else {
                // Remove from global: clean symlinks or physical folders safely backed up in vault
                if isSymlink(at: targetURL) || (try? fm.destinationOfSymbolicLink(atPath: targetURL.path)) != nil {
                    try? fm.removeItem(at: targetURL)
                } else if fm.fileExists(atPath: targetURL.path) {
                    if !fm.fileExists(atPath: vaultSkillURL.path) {
                        try? fm.copyItem(at: targetURL, to: vaultSkillURL)
                    }
                    if fm.fileExists(atPath: vaultSkillURL.path) {
                        try? fm.removeItem(at: targetURL)
                    }
                }
            }
        }

        syncClaudeGlobalSkills(allSkills: allSkills, enabledSkillIds: enabledSkillIds)
    }

    // MARK: - Global Plugins Sync
    public func syncGlobalPlugins(allPlugins: [PluginDefinition], enabledPluginIds: Set<String>) throws {
        let globalPluginsDir = PathConstants.globalPluginsDirectory
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory

        try fm.createDirectory(at: globalPluginsDir, withIntermediateDirectories: true)

        for plugin in allPlugins {
            let targetURL = globalPluginsDir.appendingPathComponent(plugin.id)
            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourceURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)

            if enabledPluginIds.contains(plugin.id) {
                let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                if let symlinkDest {
                    if symlinkDest != sourceURL.path {
                        try? fm.removeItem(at: targetURL)
                        if fm.fileExists(atPath: sourceURL.path) {
                            try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                        }
                    }
                } else if !fm.fileExists(atPath: targetURL.path) {
                    if fm.fileExists(atPath: sourceURL.path) {
                        try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                    }
                }
            } else {
                if isSymlink(at: targetURL) || (try? fm.destinationOfSymbolicLink(atPath: targetURL.path)) != nil {
                    try? fm.removeItem(at: targetURL)
                } else if fm.fileExists(atPath: targetURL.path) {
                    if !fm.fileExists(atPath: vaultPluginURL.path) {
                        try? fm.copyItem(at: targetURL, to: vaultPluginURL)
                    }
                    if fm.fileExists(atPath: vaultPluginURL.path) {
                        try? fm.removeItem(at: targetURL)
                    }
                }
            }
        }

        syncClaudeGlobalPlugins(allPlugins: allPlugins, enabledPluginIds: enabledPluginIds)
    }

    // MARK: - Claude Sync Helpers
    public func loadOAuthTokens() -> [String: String] {
        let oauthFile = PathConstants.engineMCPOAuthTokensFile.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: oauthFile),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (url, entry) in dict {
            if let tokenObj = entry["token"] as? [String: Any],
               let accessToken = tokenObj["access_token"] as? String,
               !accessToken.isEmpty {
                result[url] = accessToken
            }
        }
        return result
    }

    public func convertToClaudeMCPConfig(_ rawDict: [String: Any]) -> [String: Any] {
        var converted = rawDict
        converted.removeValue(forKey: "disabled")

        if let serverUrl = (converted["serverUrl"] as? String) ?? (converted["url"] as? String), !serverUrl.isEmpty {
            converted.removeValue(forKey: "serverUrl")
            converted["type"] = "http"
            converted["url"] = serverUrl

            let headers = (converted["headers"] as? [String: String]) ?? [:]
            if !headers.isEmpty {
                converted["headers"] = headers
            } else {
                converted.removeValue(forKey: "headers")
            }

            converted["headersHelper"] = PathConstants.claudeMCPOAuthHelperScript.path
        } else if converted["command"] != nil {
            converted["type"] = "stdio"
        }
        return converted
    }

    public func ensureClaudeEnvironment() {
        let hooksDir = PathConstants.claudeHooksDirectory
        try? fm.createDirectory(at: hooksDir, withIntermediateDirectories: true)

        let helperScript = PathConstants.claudeMCPOAuthHelperScript
        let existingScript = try? String(contentsOf: helperScript, encoding: .utf8)
        if existingScript != Self.mcpOAuthHeadersScriptContent {
            try? Self.mcpOAuthHeadersScriptContent.write(to: helperScript, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScript.path)

        // Ensure ~/.claude/settings.json auto-approves project MCPs. Plugins and claude.ai connectors stay the user's choice.
        let settingsFile = PathConstants.claudeSettingsFile.resolvingSymlinksInPath()
        var settingsDict: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: settingsFile),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            settingsDict = existingJSON
        }
        var settingsChanged = false
        if (settingsDict["enableAllProjectMcpServers"] as? Bool) != true {
            settingsDict["enableAllProjectMcpServers"] = true
            settingsChanged = true
        }
        if settingsChanged,
           let data = try? JSONSerialization.data(withJSONObject: settingsDict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settingsFile, options: .atomic)
        }

        // Clear stale mcp-needs-auth-cache.json across primary and profile homes
        for cacheFile in PathConstants.allClaudeNeedsAuthCacheFiles {
            if fm.fileExists(atPath: cacheFile.path) {
                try? "{}".write(to: cacheFile, atomically: true, encoding: .utf8)
            }
        }
    }

    public func syncClaudeGlobalConfig(servers: [MCPServerDefinition], enabledIds: Set<String>) {
        let claudeDir = PathConstants.claudeDirectory
        try? fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        ensureClaudeEnvironment()

        // Ensure ~/.claude/CLAUDE.md points to ~/.gemini/GEMINI.md
        let geminiMd = PathConstants.geminiGlobalMemoryFile.resolvingSymlinksInPath()
        let claudeMd = PathConstants.claudeGlobalMemoryFile
        if fm.fileExists(atPath: geminiMd.path) {
            let currentDest = try? fm.destinationOfSymbolicLink(atPath: claudeMd.path)
            if currentDest != geminiMd.path {
                try? fm.removeItem(at: claudeMd)
                try? fm.createSymbolicLink(at: claudeMd, withDestinationURL: geminiMd)
            }
        }

        for configFile in PathConstants.allClaudeConfigFiles {
            let claudeConfigURL = configFile.resolvingSymlinksInPath()
            var rootDict: [String: Any] = [:]
            if let existingData = try? Data(contentsOf: claudeConfigURL),
               let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                rootDict = existingJSON
            }

            var claudeServers: [String: Any] = [:]
            for server in servers where enabledIds.contains(server.id) {
                let raw = server.config.mapValues { $0.toAny() }
                claudeServers[server.id] = convertToClaudeMCPConfig(raw)
            }

            // Claude Code writes this file constantly, so touch it only when there is a real change.
            guard (rootDict["mcpServers"] as? NSDictionary) != (claudeServers as NSDictionary) else { continue }
            rootDict["mcpServers"] = claudeServers
            if let data = try? JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: claudeConfigURL, options: .atomic)
            }
        }
    }

    public func syncClaudeGlobalSkills(allSkills: [SkillDefinition], enabledSkillIds: Set<String>) {
        let claudeSkillsDir = PathConstants.claudeGlobalSkillsDirectory
        let vaultSkillsDir = PathConstants.vaultSkillsDirectory
        try? fm.createDirectory(at: claudeSkillsDir, withIntermediateDirectories: true)

        for skill in allSkills {
            guard skill.id != "synced" && !skill.id.hasPrefix(".") else { continue }
            let targetURL = claudeSkillsDir.appendingPathComponent(skill.id)
            let vaultSkillURL = vaultSkillsDir.appendingPathComponent(skill.id)
            let sourceURL = fm.fileExists(atPath: vaultSkillURL.path)
                ? vaultSkillURL
                : URL(fileURLWithPath: skill.path)

            if enabledSkillIds.contains(skill.id) {
                let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                if let symlinkDest {
                    if symlinkDest != sourceURL.path {
                        try? fm.removeItem(at: targetURL)
                        if fm.fileExists(atPath: sourceURL.path) {
                            try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                        }
                    }
                } else if !fm.fileExists(atPath: targetURL.path), fm.fileExists(atPath: sourceURL.path) {
                    try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                }
            } else {
                if isSymlink(at: targetURL) || (try? fm.destinationOfSymbolicLink(atPath: targetURL.path)) != nil {
                    try? fm.removeItem(at: targetURL)
                }
            }
        }

        // Propagate shared ~/.claude resources (skills, CLAUDE.md, hooks, settings.json, projects, plans) into AntigravityProfiles
        let primaryClaudeDir = PathConstants.claudeDirectory
        for subDir in ["projects", "plans"] {
            try? fm.createDirectory(at: primaryClaudeDir.appendingPathComponent(subDir, isDirectory: true), withIntermediateDirectories: true)
        }
        for profHome in PathConstants.antigravityProfileHomes {
            let profClaudeDir = profHome.appendingPathComponent(".claude", isDirectory: true)
            try? fm.createDirectory(at: profClaudeDir, withIntermediateDirectories: true)
            for item in ["skills", "CLAUDE.md", "hooks", "settings.json", "projects", "plans"] {
                let srcItem = primaryClaudeDir.appendingPathComponent(item)
                let dstItem = profClaudeDir.appendingPathComponent(item)
                guard fm.fileExists(atPath: srcItem.path) || (try? fm.destinationOfSymbolicLink(atPath: srcItem.path)) != nil else { continue }
                if (try? fm.destinationOfSymbolicLink(atPath: dstItem.path)) != srcItem.path {
                    try? fm.removeItem(at: dstItem)
                    try? fm.createSymbolicLink(at: dstItem, withDestinationURL: srcItem)
                }
            }
        }
    }

    public func syncClaudeGlobalPlugins(allPlugins: [PluginDefinition], enabledPluginIds: Set<String>) {
        let claudeSkillsDir = PathConstants.claudeGlobalSkillsDirectory
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory
        try? fm.createDirectory(at: claudeSkillsDir, withIntermediateDirectories: true)

        var pluginClaudeServers: [String: [String: Any]] = [:]

        for plugin in allPlugins {
            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourcePluginURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)

            // 1. Plugin bundled skills -> ~/.claude/skills/
            let pluginSkillsDir = sourcePluginURL.appendingPathComponent("skills", isDirectory: true)
            if let subSkills = try? fm.contentsOfDirectory(at: pluginSkillsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for subSkillURL in subSkills {
                    let subSkillId = subSkillURL.lastPathComponent
                    guard subSkillId != "synced" else { continue }
                    let targetURL = claudeSkillsDir.appendingPathComponent(subSkillId)
                    if enabledPluginIds.contains(plugin.id) {
                        let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                        if symlinkDest != subSkillURL.path {
                            try? fm.removeItem(at: targetURL)
                            try? fm.createSymbolicLink(at: targetURL, withDestinationURL: subSkillURL)
                        }
                    } else {
                        if let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path),
                           symlinkDest == subSkillURL.path {
                            try? fm.removeItem(at: targetURL)
                        }
                    }
                }
            }

            // 2. Plugin bundled MCP servers -> ~/.claude.json
            let pluginMCPFile = sourcePluginURL.appendingPathComponent("mcp_config.json")
            if let data = try? Data(contentsOf: pluginMCPFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pluginServers = json["mcpServers"] as? [String: [String: Any]] {
                for (serverId, rawConfig) in pluginServers {
                    if enabledPluginIds.contains(plugin.id) {
                        pluginClaudeServers[serverId] = convertToClaudeMCPConfig(rawConfig)
                    }
                }
            }
        }

        if !pluginClaudeServers.isEmpty {
            for configFile in PathConstants.allClaudeConfigFiles {
                let claudeConfigURL = configFile.resolvingSymlinksInPath()
                var rootDict: [String: Any] = [:]
                if let existingData = try? Data(contentsOf: claudeConfigURL),
                   let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                    rootDict = existingJSON
                }
                var claudeServers = (rootDict["mcpServers"] as? [String: Any]) ?? [:]
                for (serverId, converted) in pluginClaudeServers {
                    claudeServers[serverId] = converted
                }
                rootDict["mcpServers"] = claudeServers
                if let data = try? JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: claudeConfigURL, options: .atomic)
                }
            }
        }
    }
}

