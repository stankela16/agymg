import Foundation
import CryptoKit
import Darwin

extension SyncEngine {
    public static let managedMarkerFilename = ".agymg-managed"

    private struct ManagedCopyMarker: Codable {
        let managedBy: String
        let sourcePath: String
        let fingerprint: String
    }

    // MARK: - Project Sync
    public func syncProject(
        project: ProjectProfile,
        allServers: [MCPServerDefinition],
        allSkills: [SkillDefinition],
        allPlugins: [PluginDefinition]
    ) throws {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: project.path)
        guard fm.fileExists(atPath: projectURL.path) else { return }

        _ = createConfigSnapshotIfNeeded(force: false)

        let agentsDir = projectURL.appendingPathComponent(".agents", isDirectory: true)

        // 1. Sync Project MCP Servers (via .agents/plugins/agy-manager), skipping any server already bundled
        // inside an enabled project plugin so Antigravity never loads duplicate MCP instances.
        let pluginDir = agentsDir.appendingPathComponent("plugins/agy-manager", isDirectory: true)
        let serverMap = Dictionary(uniqueKeysWithValues: allServers.map { ($0.id, $0) })
        let bundledIndex = PluginScannerService.bundledMCPIndex(
            for: allPlugins,
            enabledPluginIds: project.enabledPluginIds
        )
        let validServerIds = project.enabledMCPServerIds.filter { serverId in
            guard PathConstants.isSafeResourceId(serverId) else { return false }
            return bundledIndex.conflictingPluginId(for: serverId, server: serverMap[serverId]) == nil
        }

        var projectServers: [String: [String: Any]] = [:]
        for serverId in validServerIds {
            if let server = serverMap[serverId] {
                var raw = server.config.mapValues { $0.toAny() }
                raw.removeValue(forKey: "disabled")
                projectServers[serverId] = raw
            }
        }

        let shouldRemoveAgyManager = validServerIds.isEmpty || (!allServers.isEmpty && projectServers.isEmpty)
        if shouldRemoveAgyManager {
            if fm.fileExists(atPath: pluginDir.path) || isSymlink(at: pluginDir) {
                try? fm.removeItem(at: pluginDir)
            }
        } else {
            // Only protect .gitignore when this is a git repository AND agymg is writing project MCP configs
            if fm.fileExists(atPath: projectURL.appendingPathComponent(".git").path) {
                ensureGitignore(at: projectURL)
            }

            try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

            let pluginJsonURL = pluginDir.appendingPathComponent("plugin.json")
            let pluginMeta: [String: Any] = ["name": "agy-manager"]
            let metaData = try JSONSerialization.data(withJSONObject: pluginMeta, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try metaData.write(to: pluginJsonURL, options: .atomic)

            let mcpConfigURL = pluginDir.appendingPathComponent("mcp_config.json")
            let mcpPayload: [String: Any] = ["mcpServers": projectServers]
            let mcpData = try JSONSerialization.data(withJSONObject: mcpPayload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try PathConstants.writeSecureData(mcpData, to: mcpConfigURL, permissions: 0o600)
        }

        // 2. Sync Project Skills as workspace-local managed copies (.agents/skills/<id>)
        // Antigravity rejects symlinks and manifest paths that escape the workspace root.
        let projectSkillsDir = agentsDir.appendingPathComponent("skills", isDirectory: true)
        let vaultSkillsDir = PathConstants.vaultSkillsDirectory
        let skillSync = try syncManagedProjectResources(
            items: allSkills.map { ($0.id, $0.path) },
            enabledIds: project.enabledSkillIds,
            projectURL: projectURL,
            projectItemsDir: projectSkillsDir,
            relativeItemsDir: ".agents/skills",
            vaultItemsDir: vaultSkillsDir
        )

        // Keep committed local .claude/skills visible to Antigravity via in-workspace relative path in .agents/skills.json,
        // while pruning any legacy out-of-workspace Vault manifest entries.
        let claudeLocalSkillsDir = projectURL.appendingPathComponent(".claude/skills", isDirectory: true)
        let claudeLocalIds = collectAndCleanClaudeLocalSkillIds(
            projectURL: projectURL,
            claudeSkillsDir: claudeLocalSkillsDir,
            agentsSkillsDir: projectSkillsDir
        ).filter { !skillSync.includedIds.contains($0) }

        var desiredSkillManifestGroups: [(path: String, includeOnly: [String]?)] = []
        if !claudeLocalIds.isEmpty {
            desiredSkillManifestGroups.append((path: ".claude/skills", includeOnly: claudeLocalIds))
        }

        try syncDiscoveryManifest(
            at: agentsDir.appendingPathComponent("skills.json"),
            projectURL: projectURL,
            relativeManifestPath: ".agents/skills.json",
            desiredGroups: desiredSkillManifestGroups,
            managedDirPaths: skillSync.managedDirPaths,
            managedSinglePaths: skillSync.managedSinglePaths,
            replaceIncludeOnlyPaths: [
                Self.resolveEvenIfMissing(claudeLocalSkillsDir),
                claudeLocalSkillsDir.standardizedFileURL.path,
                ".claude/skills"
            ],
            pruneAllVaultEntries: true
        )

        // 3. Sync Project Plugins as workspace-local managed copies (.agents/plugins/<id>), keeping agy-manager physical
        let projectPluginsDir = agentsDir.appendingPathComponent("plugins", isDirectory: true)
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory
        let pluginSync = try syncManagedProjectResources(
            items: allPlugins.map { ($0.id, $0.path) },
            enabledIds: project.enabledPluginIds,
            projectURL: projectURL,
            projectItemsDir: projectPluginsDir,
            relativeItemsDir: ".agents/plugins",
            vaultItemsDir: vaultPluginsDir,
            excludedIds: ["agy-manager"],
            backupDisabledPhysicalToVault: true,
            restrictMCPConfigPermissions: true
        )

        // Prune any legacy out-of-workspace Vault entries from .agents/plugins.json while preserving user/team entries.
        try syncDiscoveryManifest(
            at: agentsDir.appendingPathComponent("plugins.json"),
            projectURL: projectURL,
            relativeManifestPath: ".agents/plugins.json",
            desiredGroups: [],
            managedDirPaths: pluginSync.managedDirPaths,
            managedSinglePaths: pluginSync.managedSinglePaths,
            replaceIncludeOnlyPaths: [],
            pruneAllVaultEntries: true
        )

        // 4. Sync Project MCP Servers to Claude (~/.claude.json -> projects[project.path].mcpServers)
        syncClaudeProjectMCP(project: project, allServers: allServers, allPlugins: allPlugins)

        // 5. Sync Project Skills & Plugin Skills to Claude (<project>/.claude/skills/<skill-id>)
        syncClaudeProjectSkills(project: project, allSkills: allSkills, allPlugins: allPlugins)
    }

    public func syncClaudeProjectSkills(
        project: ProjectProfile,
        allSkills: [SkillDefinition],
        allPlugins: [PluginDefinition]
    ) {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: project.path)
        let vaultSkillsDir = PathConstants.vaultSkillsDirectory
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory

        var desiredSkillSources: [String: URL] = [:]

        // 1. Enabled Vault / Global skills for this project
        for skill in allSkills where PathConstants.isSafeResourceId(skill.id) && project.enabledSkillIds.contains(skill.id) {
            let vaultSkillURL = vaultSkillsDir.appendingPathComponent(skill.id)
            let sourceURL = fm.fileExists(atPath: vaultSkillURL.path)
                ? vaultSkillURL
                : URL(fileURLWithPath: skill.path)
            if fm.fileExists(atPath: sourceURL.path) {
                desiredSkillSources[skill.id] = sourceURL
            }
        }

        // 2. Local project skills in <project>/.agents/skills/ (excluding agymg-managed Vault copies)
        let agentsSkillsDir = projectURL.appendingPathComponent(".agents/skills", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(at: agentsSkillsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items {
                let skillId = item.lastPathComponent
                guard PathConstants.isSafeResourceId(skillId) else { continue }
                guard !Self.isManagedCopy(at: item) else { continue }
                if desiredSkillSources[skillId] == nil && fm.fileExists(atPath: item.path) {
                    desiredSkillSources[skillId] = item.resolvingSymlinksInPath()
                }
            }
        }

        // 3. Skills bundled inside enabled project plugins (<plugin>/skills/*)
        for plugin in allPlugins where PathConstants.isSafeResourceId(plugin.id) && project.enabledPluginIds.contains(plugin.id) && plugin.id != "agy-manager" {
            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourcePluginURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)
            let pluginSkillsDir = sourcePluginURL.appendingPathComponent("skills", isDirectory: true)
            if let subSkills = try? fm.contentsOfDirectory(at: pluginSkillsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for subSkill in subSkills where fm.fileExists(atPath: subSkill.path) {
                    let subId = subSkill.lastPathComponent
                    guard PathConstants.isSafeResourceId(subId) else { continue }
                    if desiredSkillSources[subId] == nil {
                        desiredSkillSources[subId] = subSkill.resolvingSymlinksInPath()
                    }
                }
            }
        }

        let claudeSkillsDir = projectURL.appendingPathComponent(".claude/skills", isDirectory: true)

        // Clean up any stale symlinks in <project>/.claude/skills/ that are no longer enabled (never delete real directories)
        var removedClaudeExcludes: Set<String> = []
        if let existingItems = try? fm.contentsOfDirectory(at: claudeSkillsDir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            for item in existingItems {
                let name = item.lastPathComponent
                if desiredSkillSources[name] == nil && isSymlink(at: item) {
                    try? fm.removeItem(at: item)
                    removedClaudeExcludes.insert(".claude/skills/\(name)")
                }
            }
        }
        removeGitExcludeEntries(at: projectURL, entries: removedClaudeExcludes)

        guard !desiredSkillSources.isEmpty else { return }

        try? fm.createDirectory(at: claudeSkillsDir, withIntermediateDirectories: true)
        var createdSymlinkNames: [String] = []

        for (skillId, sourceURL) in desiredSkillSources where PathConstants.isSafeResourceId(skillId) {
            let targetURL = claudeSkillsDir.appendingPathComponent(skillId)
            if isSymlink(at: targetURL) {
                let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                if symlinkDest != sourceURL.path {
                    try? fm.removeItem(at: targetURL)
                    try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                }
                createdSymlinkNames.append(skillId)
            } else if !fm.fileExists(atPath: targetURL.path) {
                try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                createdSymlinkNames.append(skillId)
            }
        }

        // Ensure local .git/info/exclude hides symlinked .claude/skills entries so git status stays 100% clean without touching .gitignore
        ensureGitExcludeForSkills(at: projectURL, directory: ".claude/skills", symlinkedSkillIds: createdSymlinkNames)
    }

    /// A skill created in <project>/.claude/skills is a real folder, often committed, so it stays there:
    /// referencing it via .agents/skills.json is enough for Antigravity to see it.
    public func linkClaudeProjectSkills(project: ProjectProfile) {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: project.path)
        let agentsDir = projectURL.appendingPathComponent(".agents", isDirectory: true)
        let manifestURL = agentsDir.appendingPathComponent("skills.json")
        let claudeSkillsDir = projectURL.appendingPathComponent(".claude/skills", isDirectory: true)
        let agentsSkillsDir = agentsDir.appendingPathComponent("skills", isDirectory: true)

        let manifestExists = fm.fileExists(atPath: manifestURL.path)
        guard fm.fileExists(atPath: claudeSkillsDir.path) || manifestExists else { return }

        let claudeLocalIds = collectAndCleanClaudeLocalSkillIds(
            projectURL: projectURL,
            claudeSkillsDir: claudeSkillsDir,
            agentsSkillsDir: agentsSkillsDir
        )

        guard !claudeLocalIds.isEmpty || manifestExists else { return }

        let desiredGroups: [(path: String, includeOnly: [String]?)] = claudeLocalIds.isEmpty
            ? []
            : [(path: ".claude/skills", includeOnly: claudeLocalIds)]

        try? syncDiscoveryManifest(
            at: manifestURL,
            projectURL: projectURL,
            relativeManifestPath: ".agents/skills.json",
            desiredGroups: desiredGroups,
            managedDirPaths: [],
            managedSinglePaths: [],
            replaceIncludeOnlyPaths: [
                Self.resolveEvenIfMissing(claudeSkillsDir),
                claudeSkillsDir.standardizedFileURL.path,
                ".claude/skills"
            ],
            pruneAllVaultEntries: false
        )
    }

    private func ensureGitExcludeForSkills(at projectURL: URL, directory: String, symlinkedSkillIds: [String]) {
        ensureGitExcludeEntries(at: projectURL, entries: symlinkedSkillIds.map { "\(directory)/\($0)" })
    }

    func ensureGitExcludeEntries(at projectURL: URL, entries: [String]) {
        guard !entries.isEmpty else { return }
        let fm = FileManager.default
        let gitExcludeURL = projectURL.appendingPathComponent(".git/info/exclude")
        guard fm.fileExists(atPath: gitExcludeURL.deletingLastPathComponent().path) else { return }

        let existingContent = (try? String(contentsOf: gitExcludeURL, encoding: .utf8)) ?? ""
        let existingLines = Set(existingContent.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) })

        var linesToAdd: [String] = []
        for entry in entries.sorted() {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let rootDirectory = String(trimmed.prefix { $0 != "/" })
            let alreadyExcluded = existingLines.contains(trimmed)
                || (!rootDirectory.isEmpty && (
                    existingLines.contains("\(rootDirectory)/")
                    || existingLines.contains(rootDirectory)
                    || existingLines.contains("\(rootDirectory)/*")
                ))
            if !alreadyExcluded {
                linesToAdd.append(trimmed)
            }
        }

        guard !linesToAdd.isEmpty else { return }
        var updated = existingContent
        if !updated.isEmpty && !updated.hasSuffix("\n") {
            updated += "\n"
        }
        updated += linesToAdd.joined(separator: "\n") + "\n"
        try? updated.write(to: gitExcludeURL, atomically: true, encoding: .utf8)
    }

    func removeGitExcludeEntries(at projectURL: URL, entries: Set<String>) {
        guard !entries.isEmpty else { return }
        let fm = FileManager.default
        let gitExcludeURL = projectURL.appendingPathComponent(".git/info/exclude")
        guard fm.fileExists(atPath: gitExcludeURL.path),
              let existingContent = try? String(contentsOf: gitExcludeURL, encoding: .utf8) else {
            return
        }

        let hadTrailingNewline = existingContent.hasSuffix("\n")
        let lines = existingContent.components(separatedBy: .newlines)
        let filtered = lines.filter { !entries.contains($0.trimmingCharacters(in: .whitespaces)) }
        guard filtered.count != lines.count else { return }

        var updated = filtered.joined(separator: "\n")
        if hadTrailingNewline && !updated.isEmpty && !updated.hasSuffix("\n") {
            updated += "\n"
        }
        try? updated.write(to: gitExcludeURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Managed Local Copy Helpers (.agents/skills/<id> & .agents/plugins/<id>)
    private struct ManagedSyncResult {
        var activeManagedIds: Set<String> = []
        var includedIds: Set<String> = []
        var managedDirPaths: Set<String> = []
        var managedSinglePaths: Set<String> = []
    }

    nonisolated public static func isManagedCopy(at url: URL) -> Bool {
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return false
        }
        return fm.fileExists(atPath: url.appendingPathComponent(managedMarkerFilename).path)
    }

    nonisolated private static func readManagedMarker(at url: URL) -> ManagedCopyMarker? {
        let markerURL = url.appendingPathComponent(managedMarkerFilename)
        guard let data = try? Data(contentsOf: markerURL) else { return nil }
        return try? JSONDecoder().decode(ManagedCopyMarker.self, from: data)
    }

    nonisolated public static func computeDirectoryFingerprint(at rootURL: URL) -> String {
        let fm = FileManager.default
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"

        guard let enumerator = fm.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else {
            return PathConstants.stableShortHash("EMPTY", length: 64)
        }

        var entries: [String] = []
        for case let itemURL as URL in enumerator {
            let name = itemURL.lastPathComponent
            if name == ".DS_Store" || name == managedMarkerFilename {
                continue
            }

            let itemPath = itemURL.standardizedFileURL.path
            let relPath = itemPath.hasPrefix(rootPrefix)
                ? String(itemPath.dropFirst(rootPrefix.count))
                : name

            if let linkDest = try? fm.destinationOfSymbolicLink(atPath: itemURL.path) {
                entries.append("L|\(relPath)|\(linkDest)")
                continue
            }

            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                entries.append("D|\(relPath)")
            } else {
                let size = values?.fileSize ?? 0
                if size <= 65_536, let fileData = try? Data(contentsOf: itemURL) {
                    let digest = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
                    entries.append("F|\(relPath)|\(size)|\(digest)")
                } else {
                    let mtimeUs = Int64(((values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000_000).rounded())
                    entries.append("F|\(relPath)|\(size)|\(mtimeUs)")
                }
            }
        }

        entries.sort()
        let payload = entries.isEmpty ? "EMPTY" : entries.joined(separator: "\n")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func installManagedCopy(
        from resolvedSourceURL: URL,
        to targetURL: URL,
        parentDir: URL,
        fingerprint: String,
        restrictMCPConfigPermissions: Bool
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let stagingURL = parentDir.appendingPathComponent(".agymg_stage_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.copyItem(at: resolvedSourceURL, to: stagingURL)

            let existingMarker = stagingURL.appendingPathComponent(Self.managedMarkerFilename)
            if fm.fileExists(atPath: existingMarker.path) {
                try? fm.removeItem(at: existingMarker)
            }

            if restrictMCPConfigPermissions {
                let mcpURL = stagingURL.appendingPathComponent("mcp_config.json")
                if fm.fileExists(atPath: mcpURL.path) {
                    _ = Darwin.chmod(mcpURL.path, 0o600)
                }
            }

            let marker = ManagedCopyMarker(
                managedBy: "agymg",
                sourcePath: resolvedSourceURL.path,
                fingerprint: fingerprint
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let markerData = try encoder.encode(marker)
            try markerData.write(to: existingMarker, options: .atomic)

            if fm.fileExists(atPath: targetURL.path) {
                do {
                    _ = try fm.replaceItemAt(targetURL, withItemAt: stagingURL, backupItemName: nil, options: [])
                } catch {
                    try fm.removeItem(at: targetURL)
                    try fm.moveItem(at: stagingURL, to: targetURL)
                }
            } else {
                try fm.moveItem(at: stagingURL, to: targetURL)
            }
        } catch {
            try? fm.removeItem(at: stagingURL)
            throw error
        }
    }

    private func syncManagedProjectResources(
        items: [(id: String, path: String)],
        enabledIds: Set<String>,
        projectURL: URL,
        projectItemsDir: URL,
        relativeItemsDir: String,
        vaultItemsDir: URL,
        excludedIds: Set<String> = [],
        backupDisabledPhysicalToVault: Bool = false,
        restrictMCPConfigPermissions: Bool = false
    ) throws -> ManagedSyncResult {
        let fm = FileManager.default
        var result = ManagedSyncResult()
        var activeExcludeEntries: [String] = []
        var removedExcludeEntries: Set<String> = []

        result.managedDirPaths.insert(Self.resolveEvenIfMissing(vaultItemsDir))
        result.managedDirPaths.insert(vaultItemsDir.standardizedFileURL.path)

        for item in items where PathConstants.isSafeResourceId(item.id) && !excludedIds.contains(item.id) {
            let targetURL = projectItemsDir.appendingPathComponent(item.id, isDirectory: true)
            let vaultItemURL = vaultItemsDir.appendingPathComponent(item.id, isDirectory: true)
            let sourceURL = fm.fileExists(atPath: vaultItemURL.path)
                ? vaultItemURL
                : URL(fileURLWithPath: item.path)

            let resolvedSourcePath = Self.resolveEvenIfMissing(sourceURL)
            let resolvedSourceURL = URL(fileURLWithPath: resolvedSourcePath)
            if resolvedSourceURL.lastPathComponent == item.id {
                result.managedDirPaths.insert(resolvedSourceURL.deletingLastPathComponent().path)
            } else {
                result.managedSinglePaths.insert(resolvedSourceURL.path)
            }

            let targetIsSymlink = isSymlink(at: targetURL)
            if targetIsSymlink {
                try? fm.removeItem(at: targetURL)
                removedExcludeEntries.insert("\(relativeItemsDir)/\(item.id)")
            }

            let targetIsManaged = Self.isManagedCopy(at: targetURL)
            let isPhysicalLocal = fm.fileExists(atPath: targetURL.path) && !targetIsManaged

            if backupDisabledPhysicalToVault,
               !enabledIds.contains(item.id),
               isPhysicalLocal,
               !fm.fileExists(atPath: vaultItemURL.path) {
                try? fm.createDirectory(at: vaultItemsDir, withIntermediateDirectories: true)
                try? fm.copyItem(at: targetURL, to: vaultItemURL)
            }

            if enabledIds.contains(item.id) {
                if isPhysicalLocal {
                    result.includedIds.insert(item.id)
                } else if fm.fileExists(atPath: resolvedSourceURL.path) {
                    let resolvedTargetPath = Self.resolveEvenIfMissing(targetURL)
                    if resolvedSourceURL.path != resolvedTargetPath {
                        let fingerprint = Self.computeDirectoryFingerprint(at: resolvedSourceURL)
                        let isUpToDate: Bool
                        if targetIsManaged,
                           let existingMarker = Self.readManagedMarker(at: targetURL),
                           existingMarker.sourcePath == resolvedSourceURL.path,
                           existingMarker.fingerprint == fingerprint {
                            isUpToDate = true
                        } else {
                            isUpToDate = false
                        }

                        if !isUpToDate {
                            try installManagedCopy(
                                from: resolvedSourceURL,
                                to: targetURL,
                                parentDir: projectItemsDir,
                                fingerprint: fingerprint,
                                restrictMCPConfigPermissions: restrictMCPConfigPermissions
                            )
                        }
                        result.activeManagedIds.insert(item.id)
                        result.includedIds.insert(item.id)
                        activeExcludeEntries.append("\(relativeItemsDir)/\(item.id)")
                    } else {
                        result.includedIds.insert(item.id)
                    }
                } else if targetIsManaged {
                    try? fm.removeItem(at: targetURL)
                    removedExcludeEntries.insert("\(relativeItemsDir)/\(item.id)")
                }
            } else if targetIsManaged {
                try? fm.removeItem(at: targetURL)
                removedExcludeEntries.insert("\(relativeItemsDir)/\(item.id)")
            }
        }

        // Clean up orphaned managed copies and legacy Vault symlinks in projectItemsDir
        if let existingItems = try? fm.contentsOfDirectory(at: projectItemsDir, includingPropertiesForKeys: nil) {
            for entry in existingItems {
                let name = entry.lastPathComponent
                if excludedIds.contains(name) || name.hasPrefix(".agymg_stage_") {
                    continue
                }
                if isSymlink(at: entry) {
                    if let rawDest = try? fm.destinationOfSymbolicLink(atPath: entry.path) {
                        let absDest = URL(fileURLWithPath: rawDest, relativeTo: entry.deletingLastPathComponent()).standardizedFileURL.path
                        if Self.isPathInsideVault(absDest) || rawDest.contains("/.gemini/manager-vault/") {
                            try? fm.removeItem(at: entry)
                            removedExcludeEntries.insert("\(relativeItemsDir)/\(name)")
                        }
                    }
                } else if Self.isManagedCopy(at: entry) && !result.activeManagedIds.contains(name) {
                    try? fm.removeItem(at: entry)
                    removedExcludeEntries.insert("\(relativeItemsDir)/\(name)")
                }
            }
        }

        let activeSet = Set(activeExcludeEntries)
        removeGitExcludeEntries(at: projectURL, entries: removedExcludeEntries.subtracting(activeSet))
        ensureGitExcludeEntries(at: projectURL, entries: activeExcludeEntries)

        return result
    }

    // MARK: - Discovery Manifest Helpers (.agents/skills.json & .agents/plugins.json)

    nonisolated public static func resolveEvenIfMissing(_ url: URL) -> String {
        let fm = FileManager.default
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

    nonisolated public static func canonicalPathString(_ rawPath: String, relativeTo baseURL: URL) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let targetURL: URL
        if trimmed.hasPrefix("/") {
            targetURL = URL(fileURLWithPath: trimmed)
        } else if trimmed == "~" {
            targetURL = PathConstants.effectiveHomeDirectory
        } else if trimmed.hasPrefix("~/") {
            targetURL = PathConstants.effectiveHomeDirectory.appendingPathComponent(String(trimmed.dropFirst(2)))
        } else {
            targetURL = baseURL.appendingPathComponent(trimmed)
        }
        return resolveEvenIfMissing(targetURL)
    }

    nonisolated public static func isPathInsideVault(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let vaultStd = PathConstants.vaultDirectory.standardizedFileURL.path
        let vaultResolved = resolveEvenIfMissing(PathConstants.vaultDirectory)
        let candidateStd = URL(fileURLWithPath: path).standardizedFileURL.path
        let candidateResolved = resolveEvenIfMissing(URL(fileURLWithPath: path))
        return candidateStd == vaultStd
            || candidateStd.hasPrefix(vaultStd + "/")
            || candidateResolved == vaultResolved
            || candidateResolved.hasPrefix(vaultResolved + "/")
    }

    nonisolated public static func readManifestResourceIds(
        at manifestURL: URL,
        excluding excludedIds: Set<String> = []
    ) -> Set<String> {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else {
            return []
        }

        let projectURL = manifestURL.deletingLastPathComponent().deletingLastPathComponent()
        var ids: Set<String> = []

        for entry in entries {
            if let includeOnly = entry["include_only"] as? [String] {
                for rawItem in includeOnly {
                    let trimmed = rawItem.trimmingCharacters(in: .whitespacesAndNewlines)
                    let candidate = trimmed.contains("/")
                        ? URL(fileURLWithPath: trimmed).lastPathComponent
                        : trimmed
                    if PathConstants.isSafeResourceId(candidate) && !excludedIds.contains(candidate) {
                        ids.insert(candidate)
                    }
                }
            } else if let rawPath = entry["path"] as? String {
                let resolved = canonicalPathString(rawPath, relativeTo: projectURL)
                guard !resolved.isEmpty else { continue }
                let entryURL = URL(fileURLWithPath: resolved, isDirectory: true)
                let isSingleSkill = fm.fileExists(atPath: entryURL.appendingPathComponent("SKILL.md").path)
                let isSinglePlugin = fm.fileExists(atPath: entryURL.appendingPathComponent("plugin.json").path)
                    || fm.fileExists(atPath: entryURL.appendingPathComponent(".antigravity-plugin/plugin.json").path)
                    || fm.fileExists(atPath: entryURL.appendingPathComponent(".gemini-plugin/plugin.json").path)
                    || fm.fileExists(atPath: entryURL.appendingPathComponent("gemini-extension.json").path)
                if isSingleSkill || isSinglePlugin {
                    let candidate = entryURL.lastPathComponent
                    if PathConstants.isSafeResourceId(candidate) && !excludedIds.contains(candidate) {
                        ids.insert(candidate)
                    }
                }
            }
        }

        return ids
    }

    nonisolated public static func readManifestSkillIds(at projectURL: URL) -> Set<String> {
        readManifestResourceIds(at: projectURL.appendingPathComponent(".agents/skills.json"))
    }

    nonisolated public static func readManifestPluginIds(at projectURL: URL) -> Set<String> {
        readManifestResourceIds(
            at: projectURL.appendingPathComponent(".agents/plugins.json"),
            excluding: ["agy-manager"]
        )
    }

    private func collectAndCleanClaudeLocalSkillIds(
        projectURL: URL,
        claudeSkillsDir: URL,
        agentsSkillsDir: URL
    ) -> [String] {
        let fm = FileManager.default
        // No .skipsHiddenFiles: it also drops folders with the macOS `hidden` flag, which project folders here carry.
        guard let items = try? fm.contentsOfDirectory(at: claudeSkillsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var localIds: [String] = []
        for item in items where !isSymlink(at: item) && fm.fileExists(atPath: item.appendingPathComponent("SKILL.md").path) {
            let skillId = item.lastPathComponent
            guard PathConstants.isSafeResourceId(skillId) else { continue }

            let agentsTarget = agentsSkillsDir.appendingPathComponent(skillId)
            if isSymlink(at: agentsTarget),
               let rawDest = try? fm.destinationOfSymbolicLink(atPath: agentsTarget.path),
               rawDest.hasSuffix("/.claude/skills/\(skillId)") {
                try? fm.removeItem(at: agentsTarget)
            }

            let hasPhysicalAgentsSkill = fm.fileExists(atPath: agentsTarget.path) && !isSymlink(at: agentsTarget)
            if !hasPhysicalAgentsSkill {
                localIds.append(skillId)
            }
        }

        return Array(Set(localIds)).sorted()
    }

    private func syncDiscoveryManifest(
        at manifestURL: URL,
        projectURL: URL,
        relativeManifestPath: String,
        desiredGroups: [(path: String, includeOnly: [String]?)],
        managedDirPaths: Set<String>,
        managedSinglePaths: Set<String>,
        replaceIncludeOnlyPaths: Set<String>,
        pruneAllVaultEntries: Bool
    ) throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        let existingData = try? Data(contentsOf: manifestURL)
        if let existingData,
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            root = existingJSON
        }

        var newManagedByResolvedPath: [String: [String: Any]] = [:]
        var orderedManagedKeys: [String] = []
        for group in desiredGroups.sorted(by: { $0.path < $1.path }) {
            var entryDict: [String: Any] = ["path": group.path]
            if let includeOnly = group.includeOnly {
                let sortedIds = Array(Set(includeOnly)).sorted()
                guard !sortedIds.isEmpty else { continue }
                entryDict["include_only"] = sortedIds
            }
            let resolvedKey = Self.canonicalPathString(group.path, relativeTo: projectURL)
            if newManagedByResolvedPath[resolvedKey] == nil {
                orderedManagedKeys.append(resolvedKey)
            }
            newManagedByResolvedPath[resolvedKey] = entryDict
        }

        let existingEntries = (root["entries"] as? [[String: Any]]) ?? []
        var emittedKeys: Set<String> = []
        var combinedEntries: [[String: Any]] = []

        for entry in existingEntries {
            guard let rawPath = entry["path"] as? String else {
                combinedEntries.append(entry)
                continue
            }
            let resolvedPath = Self.canonicalPathString(rawPath, relativeTo: projectURL)
            let isVault = pruneAllVaultEntries && (
                Self.isPathInsideVault(resolvedPath)
                || (rawPath.hasPrefix("/") && Self.isPathInsideVault(rawPath))
            )
            let isManagedSingle = managedSinglePaths.contains(resolvedPath)
            let hasIncludeOnly = entry["include_only"] != nil
            let isManagedDir = hasIncludeOnly && managedDirPaths.contains(resolvedPath)
            let isReplaceIncludeOnly = hasIncludeOnly && replaceIncludeOnlyPaths.contains(resolvedPath)

            if isVault || isManagedSingle || isManagedDir || isReplaceIncludeOnly {
                if let replacement = newManagedByResolvedPath[resolvedPath],
                   emittedKeys.insert(resolvedPath).inserted {
                    combinedEntries.append(replacement)
                }
            } else {
                combinedEntries.append(entry)
            }
        }

        for key in orderedManagedKeys where !emittedKeys.contains(key) {
            if let entry = newManagedByResolvedPath[key] {
                combinedEntries.append(entry)
            }
        }

        if combinedEntries.isEmpty {
            root.removeValue(forKey: "entries")
        } else {
            root["entries"] = combinedEntries
        }

        if root.isEmpty {
            if fm.fileExists(atPath: manifestURL.path) || isSymlink(at: manifestURL) {
                try? fm.removeItem(at: manifestURL)
            }
            removeGitExcludeEntries(at: projectURL, entries: [relativeManifestPath])
            return
        }

        try fm.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        if existingData != data {
            try data.write(to: manifestURL, options: .atomic)
        }
        ensureGitExcludeEntries(at: projectURL, entries: [relativeManifestPath])
    }

    public func syncClaudeProjectMCP(
        project: ProjectProfile,
        allServers: [MCPServerDefinition],
        allPlugins: [PluginDefinition]
    ) {
        let fm = FileManager.default
        let oauthURLs = loadOAuthServerURLs()
        var oauthBackedIds: Set<String> = []
        let serverMap = Dictionary(uniqueKeysWithValues: allServers.map { ($0.id, $0) })
        let bundledIndex = PluginScannerService.bundledMCPIndex(
            for: allPlugins,
            enabledPluginIds: project.enabledPluginIds
        )
        var claudeProjectServers: [String: [String: Any]] = [:]

        for serverId in project.enabledMCPServerIds where PathConstants.isSafeResourceId(serverId) {
            guard let server = serverMap[serverId],
                  bundledIndex.conflictingPluginId(for: serverId, server: server) == nil else {
                continue
            }
            let raw = server.config.mapValues { $0.toAny() }
            let converted = convertToClaudeMCPConfig(raw, oauthServerURLs: oauthURLs)
            if converted["headersHelper"] != nil {
                oauthBackedIds.insert(serverId)
            }
            claudeProjectServers[serverId] = converted
        }

        // Include MCP servers bundled inside enabled project plugins (plugin definition takes precedence)
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory
        for plugin in allPlugins where PathConstants.isSafeResourceId(plugin.id) && project.enabledPluginIds.contains(plugin.id) && plugin.id != "agy-manager" {
            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourcePluginURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)
            let pluginMCPFile = sourcePluginURL.appendingPathComponent("mcp_config.json")
            if let data = try? Data(contentsOf: pluginMCPFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pluginServers = json["mcpServers"] as? [String: [String: Any]] {
                for (serverId, rawConfig) in pluginServers where PathConstants.isSafeResourceId(serverId) {
                    guard claudeProjectServers[serverId] == nil else { continue }
                    let converted = convertToClaudeMCPConfig(rawConfig, oauthServerURLs: oauthURLs)
                    if converted["headersHelper"] != nil {
                        oauthBackedIds.insert(serverId)
                    }
                    claudeProjectServers[serverId] = converted
                }
            }
        }

        if !oauthBackedIds.isEmpty {
            ensureClaudeEnvironment()
            clearStaleNeedsAuthCache(forServerIds: oauthBackedIds)
        }

        for configFile in PathConstants.allClaudeConfigFiles {
            let claudeConfigURL = configFile.resolvingSymlinksInPath()
            var rootDict: [String: Any] = [:]
            if let existingData = try? Data(contentsOf: claudeConfigURL),
               let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                rootDict = existingJSON
            }

            var projectsDict = (rootDict["projects"] as? [String: Any]) ?? [:]
            let existingEntry = projectsDict[project.path] as? [String: Any]
            let existingServers = existingEntry?["mcpServers"] as? [String: Any]

            if claudeProjectServers.isEmpty && (existingServers == nil || existingServers?.isEmpty == true) {
                continue
            }

            var projectEntry = existingEntry ?? [:]
            // Claude Code writes this file constantly, so touch it only when mcpServers actually changed.
            guard (projectEntry["mcpServers"] as? NSDictionary) != (claudeProjectServers as NSDictionary) else { continue }
            projectEntry["mcpServers"] = claudeProjectServers
            projectsDict[project.path] = projectEntry
            rootDict["projects"] = projectsDict

            if let data = try? JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? PathConstants.writeSecureData(data, to: claudeConfigURL, permissions: 0o600, preserveExistingPermissions: true)
            }
        }
    }

    public func isSymlink(at url: URL) -> Bool {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return true
        }
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return false }
        return values.isSymbolicLink == true
    }

    public func ensureGitignore(at projectURL: URL) {
        let fm = FileManager.default
        let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
        let protectionBlock = """
# Antigravity local agent configurations & MCP tokens
.agents/plugins/agy-manager/
.agents/mcp_config.json
"""

        if fm.fileExists(atPath: gitignoreURL.path) {
            guard let content = try? String(contentsOf: gitignoreURL, encoding: .utf8) else { return }

            let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            let alreadyProtected = lines.contains { rawLine in
                let line = rawLine.hasPrefix("/") ? String(rawLine.dropFirst()) : rawLine
                return line == ".agents" || line == ".agents/" || line == ".agents/*"
                    || line == ".agents/plugins" || line == ".agents/plugins/" || line == ".agents/plugins/*"
                    || line == ".agents/plugins/agy-manager" || line == ".agents/plugins/agy-manager/" || line == ".agents/plugins/agy-manager/*"
            }

            if alreadyProtected {
                return
            }

            let updated: String
            if content.hasSuffix("\n") {
                updated = content + protectionBlock + "\n"
            } else {
                updated = content + "\n\n" + protectionBlock + "\n"
            }
            try? updated.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        } else {
            let initialContent = protectionBlock + "\n"
            try? initialContent.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }
    }

    public static let mcpOAuthHeadersScriptContent = #"""
#!/usr/bin/env python3
import base64
from datetime import datetime, timedelta, timezone
import fcntl
import json
import os
import pwd
import sys
import time
import urllib.parse
import urllib.request

REFRESH_BUFFER_SECONDS = 300


def get_real_home() -> str:
    override = os.environ.get("AGYMG_GEMINI_DIR", "").strip()
    if override:
        resolved = os.path.realpath(os.path.expanduser(override))
        if os.path.basename(resolved) == ".gemini":
            return os.path.dirname(resolved)
        return resolved
    try:
        return os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir)
    except Exception:
        return os.path.realpath(os.path.expanduser("~"))


def get_jwt_exp(token: str):
    parts = token.split(".")
    if len(parts) != 3:
        return None
    try:
        padded = parts[1] + "=" * (-len(parts[1]) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded))
        exp = payload.get("exp")
        return float(exp) if exp is not None else None
    except Exception:
        return None


def get_iso_exp(expiry_str: str):
    if not expiry_str or not isinstance(expiry_str, str):
        return None
    try:
        normalized = expiry_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(normalized)
        return dt.timestamp()
    except Exception:
        return None


def is_token_expiring(token_obj: dict, buffer_sec: int = REFRESH_BUFFER_SECONDS) -> bool:
    access_token = token_obj.get("access_token")
    if not access_token or not isinstance(access_token, str):
        return True

    now = time.time()
    jwt_exp = get_jwt_exp(access_token)
    if jwt_exp is not None:
        return (jwt_exp - now) <= buffer_sec

    iso_exp = get_iso_exp(token_obj.get("expiry", ""))
    if iso_exp is not None:
        return (iso_exp - now) <= buffer_sec

    return False


def find_entry_key(data: dict, target_url: str):
    if target_url in data:
        return target_url
    norm = target_url.rstrip("/")
    for k in data.keys():
        if k.rstrip("/") == norm:
            return k
    return None


def is_allowed_token_url(token_url: str) -> bool:
    if not token_url or not isinstance(token_url, str):
        return False
    try:
        parsed = urllib.parse.urlparse(token_url)
    except Exception:
        return False
    scheme = (parsed.scheme or "").lower()
    host = (parsed.hostname or "").lower()
    if not host:
        return False
    if scheme == "https":
        return True
    if scheme == "http" and host in ("127.0.0.1", "localhost", "::1"):
        return True
    return False


def refresh_oauth_token(entry: dict):
    token_obj = entry.get("token") or {}
    refresh_token = token_obj.get("refresh_token")
    token_url = entry.get("token_url")
    client_id = entry.get("client_id")

    if not refresh_token or not is_allowed_token_url(token_url):
        return None

    form_data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    }
    if client_id:
        form_data["client_id"] = client_id

    body = urllib.parse.urlencode(form_data).encode("utf-8")
    req = urllib.request.Request(
        token_url,
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
            "User-Agent": "antigravity-mcp-oauth-helper/1.0",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=8) as resp:
        resp_data = json.loads(resp.read().decode("utf-8"))

    new_access = resp_data.get("access_token")
    if not new_access:
        return None

    updated_token = dict(token_obj)
    updated_token["access_token"] = new_access
    if resp_data.get("refresh_token"):
        updated_token["refresh_token"] = resp_data["refresh_token"]
    if resp_data.get("token_type"):
        updated_token["token_type"] = resp_data["token_type"]

    expires_in = resp_data.get("expires_in")
    exp_ts = None
    if isinstance(expires_in, (int, float)) and expires_in > 0:
        exp_ts = time.time() + float(expires_in)
    else:
        exp_ts = get_jwt_exp(new_access)

    if exp_ts is not None:
        local_dt = datetime.fromtimestamp(exp_ts, tz=timezone.utc).astimezone()
        updated_token["expiry"] = local_dt.isoformat()

    return updated_token


def clear_claude_needs_auth_cache(real_home: str, server_name: str):
    if not server_name:
        return
    cache_paths = [
        os.path.join(real_home, ".claude", "mcp-needs-auth-cache.json"),
    ]
    profiles_root = os.path.join(real_home, "AntigravityProfiles")
    if os.path.isdir(profiles_root):
        try:
            for name in os.listdir(profiles_root):
                if name.startswith("Profile"):
                    cache_paths.append(
                        os.path.join(profiles_root, name, "home", ".claude", "mcp-needs-auth-cache.json")
                    )
        except Exception:
            pass

    for cpath in cache_paths:
        if not os.path.isfile(cpath):
            continue
        lock_path = cpath + ".lock"
        lock_fd = None
        try:
            lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            try:
                orig_mode = os.stat(cpath).st_mode & 0o777
            except Exception:
                orig_mode = 0o600
            with open(cpath, "r", encoding="utf-8") as f:
                cache_data = json.load(f)
            if isinstance(cache_data, dict) and server_name in cache_data:
                del cache_data[server_name]
                tmp_path = f"{cpath}.tmp.{os.getpid()}"
                fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, orig_mode)
                try:
                    with os.fdopen(fd, "w", encoding="utf-8") as wf:
                        json.dump(cache_data, wf)
                    os.chmod(tmp_path, orig_mode)
                    os.replace(tmp_path, cpath)
                except Exception:
                    try:
                        os.unlink(tmp_path)
                    except Exception:
                        pass
        except Exception:
            pass
        finally:
            if lock_fd is not None:
                try:
                    fcntl.flock(lock_fd, fcntl.LOCK_UN)
                except Exception:
                    pass
                try:
                    os.close(lock_fd)
                except Exception:
                    pass


def load_static_headers_fallback(real_home: str, server_url: str, server_name: str) -> dict:
    norm_url = server_url.rstrip("/")
    config_file = os.path.join(real_home, ".gemini", "config", "mcp_config.json")
    if os.path.isfile(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            servers = cfg.get("mcpServers") if isinstance(cfg, dict) else {}
            if isinstance(servers, dict):
                for sid, sdict in servers.items():
                    if not isinstance(sdict, dict):
                        continue
                    surl = (sdict.get("serverUrl") or sdict.get("url") or "").rstrip("/")
                    if (server_name and sid == server_name) or (norm_url and surl == norm_url):
                        hdrs = sdict.get("headers")
                        if isinstance(hdrs, dict) and hdrs:
                            return {str(k): str(v) for k, v in hdrs.items() if v}
        except Exception:
            pass

    vault_file = os.path.join(real_home, ".gemini", "manager-vault", "master_mcp.json")
    if os.path.isfile(vault_file):
        try:
            with open(vault_file, "r", encoding="utf-8") as f:
                vault_list = json.load(f)
            if isinstance(vault_list, list):
                for item in vault_list:
                    if not isinstance(item, dict):
                        continue
                    sid = item.get("id", "")
                    sdict = item.get("config") if isinstance(item.get("config"), dict) else {}
                    surl = (sdict.get("serverUrl") or sdict.get("url") or "").rstrip("/")
                    if (server_name and sid == server_name) or (norm_url and surl == norm_url):
                        hdrs = sdict.get("headers")
                        if isinstance(hdrs, dict) and hdrs:
                            return {str(k): str(v) for k, v in hdrs.items() if v}
        except Exception:
            pass

    return {}


def main():
    server_url = os.environ.get("CLAUDE_CODE_MCP_SERVER_URL", "").strip()
    server_name = os.environ.get("CLAUDE_CODE_MCP_SERVER_NAME", "").strip()
    if not server_url and len(sys.argv) > 1:
        server_url = sys.argv[1].strip()

    if not server_url:
        sys.stdout.write("{}\n")
        return

    real_home = get_real_home()
    custom_oauth = os.environ.get("CLAUDE_CODE_MCP_OAUTH_FILE", "").strip()
    oauth_file = (
        os.path.realpath(custom_oauth)
        if custom_oauth
        else os.path.realpath(os.path.join(real_home, ".gemini", "antigravity", "mcp_oauth_tokens.json"))
    )

    fallback_headers = load_static_headers_fallback(real_home, server_url, server_name)
    if any(k.lower() == "authorization" for k in fallback_headers.keys()):
        sys.stdout.write(json.dumps(fallback_headers) + "\n")
        return

    data = {}
    if os.path.isfile(oauth_file):
        try:
            with open(oauth_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                data = loaded
        except Exception:
            data = {}

    key = find_entry_key(data, server_url)
    if key and isinstance(data.get(key), dict):
        entry = data[key]
        token_obj = entry.get("token") if isinstance(entry.get("token"), dict) else {}

        if is_token_expiring(token_obj):
            lock_path = os.path.join(os.path.dirname(oauth_file), ".mcp_oauth_tokens.lock")
            lock_fd = None
            try:
                lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
                fcntl.flock(lock_fd, fcntl.LOCK_EX)
                with open(oauth_file, "r", encoding="utf-8") as f:
                    fresh_data = json.load(f)
                fresh_entry = fresh_data.get(key, entry)
                fresh_tok = fresh_entry.get("token") if isinstance(fresh_entry.get("token"), dict) else {}
                if is_token_expiring(fresh_tok):
                    refreshed = refresh_oauth_token(fresh_entry)
                    if refreshed:
                        fresh_entry["token"] = refreshed
                        fresh_data[key] = fresh_entry
                        tmp_file = f"{oauth_file}.tmp.{os.getpid()}"
                        fd = os.open(tmp_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                        try:
                            with os.fdopen(fd, "w", encoding="utf-8") as wf:
                                json.dump(fresh_data, wf, indent=2)
                            os.chmod(tmp_file, 0o600)
                            os.replace(tmp_file, oauth_file)
                            token_obj = refreshed
                        except Exception:
                            try:
                                os.unlink(tmp_file)
                            except Exception:
                                pass
                            token_obj = fresh_tok
                    else:
                        token_obj = fresh_tok
                else:
                    token_obj = fresh_tok
            except Exception:
                pass
            finally:
                if lock_fd is not None:
                    try:
                        fcntl.flock(lock_fd, fcntl.LOCK_UN)
                    except Exception:
                        pass
                    try:
                        os.close(lock_fd)
                    except Exception:
                        pass

        access_token = token_obj.get("access_token", "")
        if access_token:
            clear_claude_needs_auth_cache(real_home, server_name)
            sys.stdout.write(json.dumps({"Authorization": f"Bearer {access_token}"}) + "\n")
            return

    if fallback_headers:
        sys.stdout.write(json.dumps(fallback_headers) + "\n")
    else:
        sys.stdout.write("{}\n")


if __name__ == "__main__":
    main()
"""#
}

