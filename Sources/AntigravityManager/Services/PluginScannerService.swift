import Foundation

public struct PluginBundledMCPIndex: Sendable, Equatable {
    /// Maps bundled MCP server ID -> owning plugin ID.
    public let pluginIdByServerId: [String: String]
    /// Maps normalized lowercase remote serverUrl -> owning plugin ID.
    public let pluginIdByNormalizedURL: [String: String]

    public static let empty = PluginBundledMCPIndex(
        pluginIdByServerId: [:],
        pluginIdByNormalizedURL: [:]
    )

    public var isEmpty: Bool {
        pluginIdByServerId.isEmpty && pluginIdByNormalizedURL.isEmpty
    }

    public var allServerIds: Set<String> {
        Set(pluginIdByServerId.keys)
    }

    public func conflictingPluginId(for serverId: String, server: MCPServerDefinition? = nil) -> String? {
        if let owner = pluginIdByServerId[serverId] {
            return owner
        }
        if let rawURL = server?.serverUrl {
            let normalized = SyncEngine.normalizeServerURL(rawURL).lowercased()
            if !normalized.isEmpty, let owner = pluginIdByNormalizedURL[normalized] {
                return owner
            }
        }
        return nil
    }
}

public struct PluginScannerService: Sendable {
    public init() {}

    /// Returns plugin IDs registered as Antigravity Marketplace installs (`installedFrom`) in config.json.
    public static func marketplaceInstalledPluginIds() -> Set<String> {
        var ids: Set<String> = []
        for configFile in PathConstants.allAntigravityConfigFiles {
            guard let data = try? Data(contentsOf: configFile),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plugins = json["plugins"] as? [String: [String: Any]] else {
                continue
            }
            for (pluginId, metadata) in plugins where PathConstants.isSafeResourceId(pluginId) {
                if metadata["installedFrom"] != nil {
                    ids.insert(pluginId)
                }
            }
        }
        return ids
    }

    public static func bundledMCPServerIds(inPluginDirectory directory: URL) -> Set<String> {
        let mcpFile = directory.appendingPathComponent("mcp_config.json")
        guard let data = try? Data(contentsOf: mcpFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            return []
        }
        return Set(servers.keys.filter { PathConstants.isSafeResourceId($0) })
    }

    public static func bundledMCPIndex(
        for plugins: [PluginDefinition],
        enabledPluginIds: Set<String>? = nil
    ) -> PluginBundledMCPIndex {
        let fm = FileManager.default
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory
        var byServerId: [String: String] = [:]
        var byURL: [String: String] = [:]

        for plugin in plugins.sorted(by: { $0.id < $1.id }) {
            guard PathConstants.isSafeResourceId(plugin.id),
                  plugin.id != "agy-manager" else {
                continue
            }
            if let enabledPluginIds, !enabledPluginIds.contains(plugin.id) {
                continue
            }

            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourcePluginURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)
            let mcpFile = sourcePluginURL.appendingPathComponent("mcp_config.json")

            guard let data = try? Data(contentsOf: mcpFile),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let servers = json["mcpServers"] as? [String: Any] else {
                continue
            }

            for (serverId, rawValue) in servers.sorted(by: { $0.key < $1.key }) {
                guard PathConstants.isSafeResourceId(serverId) else { continue }
                if byServerId[serverId] == nil {
                    byServerId[serverId] = plugin.id
                }
                if let rawDict = rawValue as? [String: Any],
                   let rawURL = (rawDict["serverUrl"] as? String) ?? (rawDict["url"] as? String) {
                    let normalized = SyncEngine.normalizeServerURL(rawURL).lowercased()
                    if !normalized.isEmpty && byURL[normalized] == nil {
                        byURL[normalized] = plugin.id
                    }
                }
            }
        }

        return PluginBundledMCPIndex(
            pluginIdByServerId: byServerId,
            pluginIdByNormalizedURL: byURL
        )
    }

    public func scanPlugins(in directory: URL) -> [PluginDefinition] {
        let fm = FileManager.default

        guard let enumerator = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return []
        }

        var results: [PluginDefinition] = []

        for folderURL in enumerator where !folderURL.lastPathComponent.hasPrefix(".") {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue {
                let pluginId = folderURL.lastPathComponent
                let mcpFile = folderURL.appendingPathComponent("mcp_config.json")
                let skillsDir = folderURL.appendingPathComponent("skills")
                let pluginJsonURL = folderURL.appendingPathComponent("plugin.json")

                var name = PluginDefinition.formatName(pluginId)
                var description = "Antigravity plugin bundle"

                if let data = try? Data(contentsOf: pluginJsonURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let jsonName = json["name"] as? String, !jsonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = PluginDefinition.formatName(jsonName)
                    }
                    if let jsonDesc = json["description"] as? String, !jsonDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        description = jsonDesc
                    }
                }

                results.append(PluginDefinition(
                    id: pluginId,
                    name: name,
                    description: description,
                    path: folderURL.path,
                    hasMCP: fm.fileExists(atPath: mcpFile.path),
                    hasSkills: fm.fileExists(atPath: skillsDir.path)
                ))
            }
        }

        return results.sorted { $0.id < $1.id }
    }

    @discardableResult
    public func autoIngestPlugins(
        from sourceDirectory: URL,
        into vaultDirectory: URL = PathConstants.vaultPluginsDirectory,
        excludingIds: Set<String> = []
    ) -> [String] {
        let fm = FileManager.default

        if !fm.fileExists(atPath: vaultDirectory.path) {
            try? fm.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
        }

        guard let enumerator = try? fm.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }

        var ingestedIds: [String] = []

        for item in enumerator where !item.lastPathComponent.hasPrefix(".") {
            let pluginId = item.lastPathComponent
            if !PathConstants.isSafeResourceId(pluginId) || excludingIds.contains(pluginId) {
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let isSymlink = (try? fm.destinationOfSymbolicLink(atPath: item.path)) != nil
                || (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true

            guard !isSymlink, !SyncEngine.isManagedCopy(at: item) else {
                continue
            }

            let destURL = vaultDirectory.appendingPathComponent(pluginId)
            let destExists = fm.fileExists(atPath: destURL.path)
                || (try? fm.destinationOfSymbolicLink(atPath: destURL.path)) != nil

            if !destExists {
                do {
                    try fm.copyItem(at: item, to: destURL)
                    ingestedIds.append(pluginId)
                } catch {
                    if !PathConstants.isRunningUnderTests {
                        print("PluginScannerService failed to auto-ingest plugin \(pluginId): \(error)")
                    }
                }
            }
        }

        return ingestedIds
    }

    public func scanVaultPlugins(readOnly: Bool = false) -> [PluginDefinition] {
        let vaultDir = PathConstants.vaultPluginsDirectory
        let fm = FileManager.default

        if !readOnly {
            if !fm.fileExists(atPath: vaultDir.path) {
                try? fm.createDirectory(at: vaultDir, withIntermediateDirectories: true)
            }
            // Auto-ingest any non-symlinked plugins from global config (~/.gemini/config/plugins) into the vault
            autoIngestPlugins(from: PathConstants.globalPluginsDirectory, into: vaultDir)
        }

        return scanPlugins(in: vaultDir)
    }

    public func scanGlobalPlugins() -> [PluginDefinition] {
        scanPlugins(in: PathConstants.globalPluginsDirectory)
    }

    public func scanProjectPlugins(at projectURL: URL) -> [PluginDefinition] {
        let pluginsDir = projectURL.appendingPathComponent(".agents/plugins", isDirectory: true)
        return scanPlugins(in: pluginsDir)
    }

    public func scanProjectPlugins(projectPath: String) -> [PluginDefinition] {
        scanProjectPlugins(at: URL(fileURLWithPath: projectPath))
    }

    public func scanAllPlugins(projects: [ProjectProfile], readOnly: Bool = false) -> [PluginDefinition] {
        let vaultDir = PathConstants.vaultPluginsDirectory
        let fm = FileManager.default

        if !readOnly {
            if !fm.fileExists(atPath: vaultDir.path) {
                try? fm.createDirectory(at: vaultDir, withIntermediateDirectories: true)
            }

            // 1. Auto-ingest global plugins
            autoIngestPlugins(from: PathConstants.globalPluginsDirectory, into: vaultDir)

            // 2. Auto-ingest project plugins (excluding agy-manager)
            for project in projects {
                let projectPluginsDir = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins", isDirectory: true)
                autoIngestPlugins(from: projectPluginsDir, into: vaultDir, excludingIds: ["agy-manager"])
            }
        }

        // 3. Scan Vault plugins
        var all = scanPlugins(in: vaultDir)

        // 4. Fallback: check global and project plugins in case any were not copied or readOnly is true
        for p in scanGlobalPlugins() {
            if !all.contains(where: { $0.id == p.id }) {
                all.append(p)
            }
        }
        for project in projects {
            let projectPlugins = scanProjectPlugins(projectPath: project.path)
            for p in projectPlugins where p.id != "agy-manager" && !SyncEngine.isManagedCopy(at: URL(fileURLWithPath: p.path)) {
                if !all.contains(where: { $0.id == p.id }) {
                    all.append(p)
                }
            }
        }
        return all.sorted { $0.id < $1.id }
    }
}
