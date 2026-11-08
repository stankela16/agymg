import Foundation

public struct PluginScannerService: Sendable {
    public init() {}

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

            guard !isSymlink else {
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
            for p in projectPlugins where p.id != "agy-manager" {
                if !all.contains(where: { $0.id == p.id }) {
                    all.append(p)
                }
            }
        }
        return all.sorted { $0.id < $1.id }
    }
}
