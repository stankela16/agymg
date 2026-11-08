import Foundation
import Darwin

public struct GlobalSelection: Codable, Sendable {
    public var enabledMCPServerIds: Set<String>
    public var enabledSkillIds: Set<String>
    public var enabledPluginIds: Set<String>

    public init(
        enabledMCPServerIds: Set<String> = [],
        enabledSkillIds: Set<String> = [],
        enabledPluginIds: Set<String> = []
    ) {
        self.enabledMCPServerIds = enabledMCPServerIds
        self.enabledSkillIds = enabledSkillIds
        self.enabledPluginIds = enabledPluginIds
    }
}

/// What was created outside the Manager and just landed in the Vault.
public struct ExternalAdoption: Sendable {
    public var serverIds: Set<String> = []
    public var skillIds: Set<String> = []
    public var projectIds: Set<String> = []

    public var isEmpty: Bool { serverIds.isEmpty && skillIds.isEmpty && projectIds.isEmpty }
}

public actor VaultService {
    private let fm = FileManager.default

    public init() {}

    public func initializeVaultIfNeeded() {
        let vaultDir = PathConstants.vaultDirectory
        if !fm.fileExists(atPath: vaultDir.path) {
            try? fm.createDirectory(at: vaultDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        _ = Darwin.chmod(vaultDir.path, 0o700)

        let vaultPluginsDir = PathConstants.vaultPluginsDirectory
        if !fm.fileExists(atPath: vaultPluginsDir.path) {
            try? fm.createDirectory(at: vaultPluginsDir, withIntermediateDirectories: true)
        }

        let vaultSkillsDir = PathConstants.vaultSkillsDirectory
        if !fm.fileExists(atPath: vaultSkillsDir.path) {
            try? fm.createDirectory(at: vaultSkillsDir, withIntermediateDirectories: true)
        }

        // Bootstrap master MCP from global config and project plugins if vault MCP file doesn't exist yet
        if !fm.fileExists(atPath: PathConstants.vaultMCPFile.path) {
            bootstrapVault()
        }
    }

    private func bootstrapVault() {
        var masterServers: [String: MCPServerDefinition] = [:]
        var initialGlobalServerIds: Set<String> = []
        var initialGlobalSkillIds: Set<String> = []

        // 1. Read existing global mcp_config.json
        if fm.fileExists(atPath: PathConstants.globalMCPConfigFile.path) {
            do {
                let data = try Data(contentsOf: PathConstants.globalMCPConfigFile)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let servers = json["mcpServers"] as? [String: Any] {
                    for (id, rawValue) in servers where PathConstants.isSafeResourceId(id) {
                        if let rawDict = rawValue as? [String: Any] {
                            let jsonDict = rawDict.mapValues { JSONValue(any: $0) }
                            let def = MCPServerDefinition(id: id, config: jsonDict)
                            masterServers[id] = def
                            let isDisabled = (rawDict["disabled"] as? Bool) ?? false
                            if !isDisabled {
                                initialGlobalServerIds.insert(id)
                            }
                        }
                    }
                }
            } catch {
                if !PathConstants.isRunningUnderTests {
                    print("VaultService bootstrap error reading global config: \(error)")
                }
            }
        }

        // 2. Bootstrap existing Claude Code MCP servers (~/.claude.json)
        for configFile in PathConstants.allClaudeConfigFiles where fm.fileExists(atPath: configFile.path) {
            let root = readJSONObject(at: configFile)
            for (id, rawDict) in mcpServers(in: root) where PathConstants.isSafeResourceId(id) {
                let converted = antigravityConfig(from: rawDict)
                if var existing = masterServers[id] {
                    if mergeMissingCredentials(from: converted, into: &existing.config) {
                        masterServers[id] = existing
                    }
                } else {
                    masterServers[id] = MCPServerDefinition(id: id, config: converted)
                }
                initialGlobalServerIds.insert(id)
            }
            if let claudeProjects = root["projects"] as? [String: [String: Any]] {
                for (_, projEntry) in claudeProjects {
                    for (id, rawDict) in mcpServers(in: projEntry) where PathConstants.isSafeResourceId(id) && masterServers[id] == nil {
                        masterServers[id] = MCPServerDefinition(id: id, config: antigravityConfig(from: rawDict))
                    }
                }
            }
        }

        // 3. Bootstrap existing global skills from Antigravity (~/.gemini/config/skills) and Claude Code (~/.claude/skills)
        // Adopt physical folders into the Vault and replace them with symlinks so toggles and edits work symmetrically.
        for skillsDir in [PathConstants.globalSkillsDirectory, PathConstants.claudeGlobalSkillsDirectory] {
            guard let items = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
                continue
            }
            for item in items where item.lastPathComponent != "synced" && !item.lastPathComponent.hasPrefix(".") {
                let skillId = item.lastPathComponent
                guard PathConstants.isSafeResourceId(skillId) else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let isLink = (try? fm.destinationOfSymbolicLink(atPath: item.path)) != nil
                let destURL = PathConstants.vaultSkillsDirectory.appendingPathComponent(skillId, isDirectory: true)
                if !isLink {
                    if !fm.fileExists(atPath: destURL.path) {
                        if (try? fm.moveItem(at: item, to: destURL)) != nil {
                            try? fm.createSymbolicLink(at: item, withDestinationURL: destURL)
                        } else if (try? fm.copyItem(at: item, to: destURL)) != nil {
                            try? fm.removeItem(at: item)
                            try? fm.createSymbolicLink(at: item, withDestinationURL: destURL)
                        }
                    } else {
                        let conflictDir = PathConstants.vaultBackupsDirectory
                            .appendingPathComponent("bootstrap-skill-conflicts", isDirectory: true)
                        try? fm.createDirectory(at: conflictDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        _ = Darwin.chmod(conflictDir.path, 0o700)
                        let originTag = skillsDir.deletingLastPathComponent().lastPathComponent
                        let backupDest = conflictDir.appendingPathComponent("\(originTag)_\(skillId)_\(UUID().uuidString.prefix(8))")
                        if (try? fm.moveItem(at: item, to: backupDest)) != nil {
                            try? fm.createSymbolicLink(at: item, withDestinationURL: destURL)
                        }
                    }
                }
                if fm.fileExists(atPath: destURL.path) || isLink {
                    initialGlobalSkillIds.insert(skillId)
                }
            }
        }

        // 4. Discover servers from project plugins and project-scoped configs when authorized
        if ProjectFolderAccessManager.shared.isAuthorized {
            let scanner = ProjectScannerService()
            let authorizedDir = ProjectFolderAccessManager.shared.authorizedDirectoryURL
            let discoveredProjects = scanner.discoverProjects(in: authorizedDir, scanDefaultWhenNil: false)

            for project in discoveredProjects {
                let pluginsDir = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins", isDirectory: true)
                if let pluginDirs = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
                    for pluginDir in pluginDirs {
                        let mcpFile = pluginDir.appendingPathComponent("mcp_config.json")
                        if let data = try? Data(contentsOf: mcpFile),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let servers = json["mcpServers"] as? [String: Any] {
                            for (id, rawValue) in servers where PathConstants.isSafeResourceId(id) {
                                if let rawDict = rawValue as? [String: Any], masterServers[id] == nil {
                                    let jsonDict = rawDict.mapValues { JSONValue(any: $0) }
                                    masterServers[id] = MCPServerDefinition(id: id, config: jsonDict)
                                }
                            }
                        }
                    }
                }
            }

            // Save projects
            saveProjects(discoveredProjects)
        }

        // Save master servers
        saveServers(Array(masterServers.values))

        // Save initial global selection
        saveGlobalSelection(GlobalSelection(enabledMCPServerIds: initialGlobalServerIds, enabledSkillIds: initialGlobalSkillIds))
    }

    public func loadServers() -> [MCPServerDefinition] {
        guard let data = try? Data(contentsOf: PathConstants.vaultMCPFile) else {
            return []
        }
        do {
            let list = try JSONDecoder().decode([MCPServerDefinition].self, from: data)
            return list.sorted { $0.id < $1.id }
        } catch {
            if !PathConstants.isRunningUnderTests {
                print("VaultService error decoding servers: \(error)")
            }
            return []
        }
    }

    public func loadServersReadOnly() -> [MCPServerDefinition] {
        if fm.fileExists(atPath: PathConstants.vaultMCPFile.path) {
            return loadServers()
        }
        var inMemory: [String: MCPServerDefinition] = [:]
        if fm.fileExists(atPath: PathConstants.globalMCPConfigFile.path),
           let data = try? Data(contentsOf: PathConstants.globalMCPConfigFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = json["mcpServers"] as? [String: Any] {
            for (id, rawValue) in servers where PathConstants.isSafeResourceId(id) {
                if let rawDict = rawValue as? [String: Any] {
                    let jsonDict = rawDict.mapValues { JSONValue(any: $0) }
                    inMemory[id] = MCPServerDefinition(id: id, config: jsonDict)
                }
            }
        }
        return inMemory.values.sorted { $0.id < $1.id }
    }

    public func scanAndIngestServers(projects: [ProjectProfile] = []) -> (servers: [MCPServerDefinition], newGlobalIds: Set<String>) {
        var masterServers: [String: MCPServerDefinition] = [:]
        for server in loadServers() {
            masterServers[server.id] = server
        }

        var newGlobalIds: Set<String> = []
        var didAdd = false

        // 1. Scan global mcp_config.json
        if fm.fileExists(atPath: PathConstants.globalMCPConfigFile.path) {
            if let data = try? Data(contentsOf: PathConstants.globalMCPConfigFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servers = json["mcpServers"] as? [String: Any] {
                for (id, rawValue) in servers where PathConstants.isSafeResourceId(id) {
                    if let rawDict = rawValue as? [String: Any] {
                        let jsonDict = rawDict.mapValues { JSONValue(any: $0) }
                        if var existing = masterServers[id] {
                            if mergeMissingCredentials(from: jsonDict, into: &existing.config) {
                                masterServers[id] = existing
                                didAdd = true
                            }
                        } else {
                            masterServers[id] = MCPServerDefinition(id: id, config: jsonDict)
                            didAdd = true
                            let isDisabled = (rawDict["disabled"] as? Bool) ?? false
                            if !isDisabled {
                                newGlobalIds.insert(id)
                            }
                        }
                    }
                }
            }
        }

        // 2. Scan projects
        for project in projects {
            let projectURL = URL(fileURLWithPath: project.path)

            // Scan .agents/plugins/*/mcp_config.json
            let pluginsDir = projectURL.appendingPathComponent(".agents/plugins", isDirectory: true)
            if let pluginDirs = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
                for pluginDir in pluginDirs {
                    let mcpFile = pluginDir.appendingPathComponent("mcp_config.json")
                    extractServers(from: mcpFile, into: &masterServers, didAdd: &didAdd)
                }
            }

            // Scan direct .agents/mcp_config.json
            let directMcpFile = projectURL.appendingPathComponent(".agents/mcp_config.json")
            extractServers(from: directMcpFile, into: &masterServers, didAdd: &didAdd)
        }

        let updatedList = Array(masterServers.values).sorted { $0.id < $1.id }
        if didAdd {
            saveServers(updatedList)
            if !newGlobalIds.isEmpty {
                var selection = loadGlobalSelection()
                selection.enabledMCPServerIds.formUnion(newGlobalIds)
                saveGlobalSelection(selection)
            }
        }

        return (updatedList, newGlobalIds)
    }

    /// Brings what was added directly in Claude Code or Antigravity into the Vault, so the next sync
    /// spreads it to both instead of deleting it. The Manager keeps being the only writer of both configs.
    public func adoptExternalChanges(
        projects: [ProjectProfile],
        ignoredServerIds: Set<String> = [],
        minimumSkillAge: TimeInterval = 30
    ) -> ExternalAdoption {
        var result = ExternalAdoption()
        var master = Dictionary(uniqueKeysWithValues: loadServers().map { ($0.id, $0) })
        var selection = loadGlobalSelection()
        var updatedProjects = projects
        // A server turned off in Antigravity is still listed in Claude until the sync, so Claude must not revive it.
        let enabledBefore = selection.enabledMCPServerIds

        func addToCatalog(_ id: String, _ raw: [String: Any]) {
            guard PathConstants.isSafeResourceId(id), master[id] == nil else { return }
            master[id] = MCPServerDefinition(id: id, config: antigravityConfig(from: raw))
            result.serverIds.insert(id)
        }

        // 1. Antigravity: the Manager writes this file, so a toggle that differs from the selection was made there.
        for (id, raw) in mcpServers(in: readJSONObject(at: PathConstants.globalMCPConfigFile)) where PathConstants.isSafeResourceId(id) && !ignoredServerIds.contains(id) {
            addToCatalog(id, raw)
            let isEnabled = !((raw["disabled"] as? Bool) ?? false)
            guard isEnabled != selection.enabledMCPServerIds.contains(id) else { continue }
            if isEnabled {
                selection.enabledMCPServerIds.insert(id)
            } else {
                selection.enabledMCPServerIds.remove(id)
            }
            result.serverIds.insert(id)
        }

        // 2. Claude Code: `claude mcp add` writes to user scope, or to the project entry by default.
        for configFile in PathConstants.allClaudeConfigFiles {
            let root = readJSONObject(at: configFile)
            for (id, raw) in mcpServers(in: root) where PathConstants.isSafeResourceId(id) && !ignoredServerIds.contains(id) {
                addToCatalog(id, raw)
                if !enabledBefore.contains(id), selection.enabledMCPServerIds.insert(id).inserted {
                    result.serverIds.insert(id)
                }
            }

            let claudeProjects = root["projects"] as? [String: [String: Any]] ?? [:]
            for index in updatedProjects.indices {
                let projectServers = mcpServers(in: claudeProjects[updatedProjects[index].path] ?? [:])
                for (id, raw) in projectServers where PathConstants.isSafeResourceId(id) && !ignoredServerIds.contains(id) {
                    addToCatalog(id, raw)
                    if updatedProjects[index].enabledMCPServerIds.insert(id).inserted {
                        result.projectIds.insert(updatedProjects[index].id)
                    }
                }
            }
        }

        // 3. Skills created in either agent move to the Vault; the sync links them back into both.
        let now = Date()
        for directory in [PathConstants.claudeGlobalSkillsDirectory, PathConstants.globalSkillsDirectory] {
            let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for item in items where item.lastPathComponent != "synced" && !item.lastPathComponent.hasPrefix(".") {
                let skillId = item.lastPathComponent
                guard PathConstants.isSafeResourceId(skillId) else { continue }
                let skillFile = item.appendingPathComponent("SKILL.md")
                let vaultURL = PathConstants.vaultSkillsDirectory.appendingPathComponent(skillId)
                guard (try? fm.destinationOfSymbolicLink(atPath: item.path)) == nil,
                      !fm.fileExists(atPath: vaultURL.path),
                      let modified = (try? fm.attributesOfItem(atPath: skillFile.path))?[.modificationDate] as? Date,
                      now.timeIntervalSince(modified) >= minimumSkillAge else { continue } // the agent may still be writing it
                if (try? fm.moveItem(at: item, to: vaultURL)) != nil {
                    selection.enabledSkillIds.insert(skillId)
                    result.skillIds.insert(skillId)
                }
            }
        }

        guard !result.isEmpty else { return result }
        saveServers(master.values.sorted { $0.id < $1.id })
        saveGlobalSelection(selection)
        if !result.projectIds.isEmpty {
            saveProjects(updatedProjects)
        }
        return result
    }

    private func readJSONObject(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func mcpServers(in container: [String: Any]) -> [String: [String: Any]] {
        container["mcpServers"] as? [String: [String: Any]] ?? [:]
    }

    /// Inverse of SyncEngine.convertToClaudeMCPConfig, so the Vault keeps a single (Antigravity) format.
    private func antigravityConfig(from raw: [String: Any]) -> [String: JSONValue] {
        var config = raw
        for key in ["type", "headersHelper", "disabled"] {
            config.removeValue(forKey: key)
        }
        if let url = config.removeValue(forKey: "url") {
            config["serverUrl"] = url
        }
        return config.mapValues { JSONValue(any: $0) }
    }

    private func extractServers(from fileURL: URL, into masterServers: inout [String: MCPServerDefinition], didAdd: inout Bool) {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            return
        }
        for (id, rawValue) in servers where PathConstants.isSafeResourceId(id) {
            if let rawDict = rawValue as? [String: Any] {
                let jsonDict = rawDict.mapValues { JSONValue(any: $0) }
                if var existing = masterServers[id] {
                    if mergeMissingCredentials(from: jsonDict, into: &existing.config) {
                        masterServers[id] = existing
                        didAdd = true
                    }
                } else {
                    masterServers[id] = MCPServerDefinition(id: id, config: jsonDict)
                    didAdd = true
                }
            }
        }
    }

    private func mergeMissingCredentials(from source: [String: JSONValue], into target: inout [String: JSONValue]) -> Bool {
        var anyChanged = false
        let isRemote = (target["serverUrl"]?.stringValue ?? target["url"]?.stringValue) != nil
        let isStdio = target["command"]?.stringValue != nil
        let allowedKeys = (isRemote ? ["headers"] : []) + (isStdio ? ["env"] : [])

        for dictKey in allowedKeys {
            guard let srcObj = source[dictKey]?.objectValue, !srcObj.isEmpty else { continue }
            var dstObj = target[dictKey]?.objectValue ?? [:]
            var keyChanged = false
            for (k, v) in srcObj {
                if let strVal = v.stringValue, !strVal.isEmpty {
                    let existingVal = dstObj[k]?.stringValue ?? ""
                    if existingVal.isEmpty {
                        dstObj[k] = v
                        keyChanged = true
                    }
                }
            }
            if keyChanged {
                target[dictKey] = .object(dstObj)
                anyChanged = true
            }
        }
        return anyChanged
    }

    private func ensureVaultDirectoryPermissions() {
        let vaultDir = PathConstants.vaultDirectory
        if !fm.fileExists(atPath: vaultDir.path) {
            try? fm.createDirectory(at: vaultDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        _ = Darwin.chmod(vaultDir.path, 0o700)
    }

    public func saveServers(_ servers: [MCPServerDefinition]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(servers)
            ensureVaultDirectoryPermissions()
            try PathConstants.writeSecureData(data, to: PathConstants.vaultMCPFile, permissions: 0o600)
        } catch {
            if !PathConstants.isRunningUnderTests {
                print("VaultService error saving servers: \(error)")
            }
        }
    }

    public func loadProjects() -> [ProjectProfile] {
        guard ProjectFolderAccessManager.shared.isAuthorized else {
            return []
        }
        let scanner = ProjectScannerService()
        let authorizedDir = ProjectFolderAccessManager.shared.authorizedDirectoryURL
        let discovered = scanner.discoverProjects(in: authorizedDir, scanDefaultWhenNil: false)

        guard let data = try? Data(contentsOf: PathConstants.vaultProjectsFile),
              let savedList = try? JSONDecoder().decode([ProjectProfile].self, from: data) else {
            saveProjects(discovered)
            return discovered
        }

        var mergedByPath: [String: ProjectProfile] = [:]
        for saved in savedList {
            if FileManager.default.fileExists(atPath: saved.path) {
                mergedByPath[saved.path] = saved
            }
        }

        for disc in discovered {
            if let existing = mergedByPath[disc.path] {
                var updated = existing
                updated.enabledMCPServerIds.formUnion(disc.enabledMCPServerIds)
                updated.enabledSkillIds.formUnion(disc.enabledSkillIds)
                updated.enabledPluginIds.formUnion(disc.enabledPluginIds)
                mergedByPath[disc.path] = updated
            } else {
                mergedByPath[disc.path] = disc
            }
        }

        let result = Array(mergedByPath.values).sorted { $0.name.lowercased() < $1.name.lowercased() }
        saveProjects(result)
        return result
    }

    public func saveProjects(_ projects: [ProjectProfile]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(projects) {
            ensureVaultDirectoryPermissions()
            try? PathConstants.writeSecureData(data, to: PathConstants.vaultProjectsFile, permissions: 0o600)
        }
    }

    public func loadGlobalSelection() -> GlobalSelection {
        guard let data = try? Data(contentsOf: PathConstants.vaultGlobalConfigFile),
              let selection = try? JSONDecoder().decode(GlobalSelection.self, from: data) else {
            return GlobalSelection()
        }
        return selection
    }

    public func saveGlobalSelection(_ selection: GlobalSelection) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(selection) {
            ensureVaultDirectoryPermissions()
            try? PathConstants.writeSecureData(data, to: PathConstants.vaultGlobalConfigFile, permissions: 0o600)
        }
    }

    public func deleteServer(id: String) {
        guard PathConstants.isSafeResourceId(id) else { return }
        var servers = loadServers()
        servers.removeAll { $0.id == id }
        saveServers(servers)
    }

    public func deleteSkill(id: String) {
        guard PathConstants.isSafeResourceId(id) else { return }
        let vaultSkillURL = PathConstants.vaultSkillsDirectory.appendingPathComponent(id)
        if fm.fileExists(atPath: vaultSkillURL.path) {
            try? fm.removeItem(at: vaultSkillURL)
        }
    }

    public func deletePlugin(id: String) {
        guard PathConstants.isSafeResourceId(id) else { return }
        let vaultPluginURL = PathConstants.vaultPluginsDirectory.appendingPathComponent(id)
        if fm.fileExists(atPath: vaultPluginURL.path) {
            try? fm.removeItem(at: vaultPluginURL)
        }
    }

    public func loadSavedProjectsWithoutTCC(allowingCWD cwd: String? = nil) -> [ProjectProfile] {
        var discovered: [ProjectProfile] = []
        if PathConstants.isRunningUnderTests || PathConstants.hasEnvironmentOverride || PathConstants.customProjectsDirectory != nil {
            let scanner = ProjectScannerService()
            discovered = scanner.discoverProjects(in: PathConstants.defaultProjectsDirectory)
        }

        guard let data = try? Data(contentsOf: PathConstants.vaultProjectsFile),
              let savedList = try? JSONDecoder().decode([ProjectProfile].self, from: data) else {
            return discovered
        }

        let normalizedCWD = cwd.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        func canSafelyStat(_ path: String) -> Bool {
            if !PathConstants.isTCCProtectedPath(path) {
                return true
            }
            guard let normalizedCWD else { return false }
            let stdPath = URL(fileURLWithPath: path).standardizedFileURL.path
            return normalizedCWD == stdPath || normalizedCWD.hasPrefix("\(stdPath)/")
        }

        var mergedByCanonicalPath: [String: ProjectProfile] = [:]
        for saved in savedList {
            if canSafelyStat(saved.path) {
                guard fm.fileExists(atPath: saved.path) else { continue }
                let key = URL(fileURLWithPath: saved.path).resolvingSymlinksInPath().path
                mergedByCanonicalPath[key] = saved
            } else {
                let key = URL(fileURLWithPath: saved.path).standardizedFileURL.path
                mergedByCanonicalPath[key] = saved
            }
        }

        for disc in discovered {
            let key = URL(fileURLWithPath: disc.path).resolvingSymlinksInPath().path
            if var existing = mergedByCanonicalPath[key] {
                existing.enabledMCPServerIds.formUnion(disc.enabledMCPServerIds)
                existing.enabledSkillIds.formUnion(disc.enabledSkillIds)
                existing.enabledPluginIds.formUnion(disc.enabledPluginIds)
                mergedByCanonicalPath[key] = existing
            } else {
                mergedByCanonicalPath[key] = disc
            }
        }

        return Array(mergedByCanonicalPath.values).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    public func loadSavedProjectsUnconditional() -> [ProjectProfile] {
        let scanner = ProjectScannerService()
        let defaultDir = PathConstants.defaultProjectsDirectory
        let shouldScanDefault = PathConstants.isRunningUnderTests
            || PathConstants.hasEnvironmentOverride
            || PathConstants.customProjectsDirectory != nil
            || !PathConstants.isTCCProtectedPath(defaultDir.path)
            || ProjectFolderAccessManager.shared.isAuthorized
        let scanRoot = ProjectFolderAccessManager.shared.authorizedDirectoryURL ?? defaultDir
        let discovered = shouldScanDefault ? scanner.discoverProjects(in: scanRoot, scanDefaultWhenNil: false) : []

        guard let data = try? Data(contentsOf: PathConstants.vaultProjectsFile),
              let savedList = try? JSONDecoder().decode([ProjectProfile].self, from: data) else {
            return discovered
        }

        var mergedByCanonicalPath: [String: ProjectProfile] = [:]
        for saved in savedList {
            if !PathConstants.isTCCProtectedPath(saved.path) || ProjectFolderAccessManager.shared.isAuthorized {
                guard fm.fileExists(atPath: saved.path) else { continue }
                let key = URL(fileURLWithPath: saved.path).resolvingSymlinksInPath().path
                mergedByCanonicalPath[key] = saved
            } else {
                let key = URL(fileURLWithPath: saved.path).standardizedFileURL.path
                mergedByCanonicalPath[key] = saved
            }
        }

        for disc in discovered {
            let key = URL(fileURLWithPath: disc.path).resolvingSymlinksInPath().path
            if var existing = mergedByCanonicalPath[key] {
                existing.enabledMCPServerIds.formUnion(disc.enabledMCPServerIds)
                existing.enabledSkillIds.formUnion(disc.enabledSkillIds)
                existing.enabledPluginIds.formUnion(disc.enabledPluginIds)
                mergedByCanonicalPath[key] = existing
            } else {
                mergedByCanonicalPath[key] = disc
            }
        }

        return Array(mergedByCanonicalPath.values).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    public func saveActiveContext(_ context: ActiveWorkspaceContext) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        ensureVaultDirectoryPermissions()
        if let data = try? encoder.encode(context) {
            try? PathConstants.writeSecureData(data, to: PathConstants.activeContextFile, permissions: 0o600)
        }
    }

    public func loadActiveContext() -> ActiveWorkspaceContext? {
        guard let data = try? Data(contentsOf: PathConstants.activeContextFile) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ActiveWorkspaceContext.self, from: data)
    }
}
