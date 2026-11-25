import XCTest
@testable import AntigravityManager

final class DiscoveryManifestSyncTests: XCTestCase {
    private var sandbox: URL!
    private let fm = FileManager.default
    private var syncEngine: SyncEngine!

    override func setUp() async throws {
        try await super.setUp()
        sandbox = fm.temporaryDirectory.appendingPathComponent("DiscoveryManifestSyncTests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = sandbox.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = sandbox.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        syncEngine = SyncEngine()
    }

    override func tearDown() async throws {
        syncEngine = nil
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let sandbox {
            try? fm.removeItem(at: sandbox)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        try await super.tearDown()
    }

    @discardableResult
    private func createVaultSkill(id: String) throws -> SkillDefinition {
        let dir = PathConstants.vaultSkillsDirectory.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: \(id)\ndescription: Vault skill \(id)\n---\n".write(
            to: dir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        return SkillDefinition(
            id: id,
            name: id,
            description: "Vault skill \(id)",
            category: "Tools",
            path: dir.path,
            origin: .vault
        )
    }

    @discardableResult
    private func createVaultPlugin(id: String) throws -> PluginDefinition {
        let dir = PathConstants.vaultPluginsDirectory.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{\"name\":\"\(id)\"}\n".write(
            to: dir.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )
        return PluginDefinition(
            id: id,
            name: id,
            description: "Vault plugin \(id)",
            path: dir.path
        )
    }

    private func createGitRepoProject(named name: String) throws -> URL {
        let projectDir = PathConstants.defaultProjectsDirectory.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: projectDir.appendingPathComponent(".git/info", isDirectory: true), withIntermediateDirectories: true)
        try "".write(to: projectDir.appendingPathComponent(".git/info/exclude"), atomically: true, encoding: .utf8)
        try "node_modules/\n".write(to: projectDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        return projectDir
    }

    func testManagedCopiesCreationGitExcludeVaultMigrationAndUpdatePropagation() async throws {
        let zSkill = try createVaultSkill(id: "z-skill")
        let aSkill = try createVaultSkill(id: "a-skill")
        let bPlugin = try createVaultPlugin(id: "b-plugin")
        let aPlugin = try createVaultPlugin(id: "a-plugin")
        let projectDir = try createGitRepoProject(named: "manifest-repo")

        // Seed legacy out-of-workspace Vault manifests (which Antigravity rejects with "escapes workspace root")
        let agentsDir = projectDir.appendingPathComponent(".agents", isDirectory: true)
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let legacySkillsManifest: [String: Any] = [
            "entries": [["path": PathConstants.vaultSkillsDirectory.resolvingSymlinksInPath().path, "include_only": ["a-skill"]]]
        ]
        try JSONSerialization.data(withJSONObject: legacySkillsManifest)
            .write(to: agentsDir.appendingPathComponent("skills.json"))
        let legacyPluginsManifest: [String: Any] = [
            "entries": [["path": PathConstants.vaultPluginsDirectory.resolvingSymlinksInPath().path, "include_only": ["a-plugin"]]]
        ]
        try JSONSerialization.data(withJSONObject: legacyPluginsManifest)
            .write(to: agentsDir.appendingPathComponent("plugins.json"))

        // ProjectAuditService flags out-of-workspace Vault manifest entries before sync
        let project = ProjectProfile(
            id: "manifest-repo",
            name: "manifest-repo",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: ["z-skill", "a-skill"],
            enabledPluginIds: ["b-plugin", "a-plugin"]
        )
        let preSyncAudit = ProjectAuditService().audit(project: project)
        XCTAssertEqual(preSyncAudit.symlinkCheck.status, .warning)

        try await syncEngine.syncProject(
            project: project,
            allServers: [],
            allSkills: [zSkill, aSkill],
            allPlugins: [bPlugin, aPlugin]
        )

        // Legacy Vault-pointing manifests are removed so Antigravity never hits workspace escape errors
        let skillsManifestURL = projectDir.appendingPathComponent(".agents/skills.json")
        let pluginsManifestURL = projectDir.appendingPathComponent(".agents/plugins.json")
        XCTAssertFalse(fm.fileExists(atPath: skillsManifestURL.path))
        XCTAssertFalse(fm.fileExists(atPath: pluginsManifestURL.path))

        // Managed local physical copies (NOT symlinks) exist inside workspace root
        for skillId in ["a-skill", "z-skill"] {
            let copiedDir = projectDir.appendingPathComponent(".agents/skills/\(skillId)", isDirectory: true)
            let isSym = await syncEngine.isSymlink(at: copiedDir)
            XCTAssertFalse(isSym, "Project skill must be a physical directory, not a symlink")
            XCTAssertTrue(SyncEngine.isManagedCopy(at: copiedDir))
            XCTAssertTrue(fm.fileExists(atPath: copiedDir.appendingPathComponent("SKILL.md").path))
        }
        for pluginId in ["a-plugin", "b-plugin"] {
            let copiedDir = projectDir.appendingPathComponent(".agents/plugins/\(pluginId)", isDirectory: true)
            let isSym = await syncEngine.isSymlink(at: copiedDir)
            XCTAssertFalse(isSym, "Project plugin must be a physical directory, not a symlink")
            XCTAssertTrue(SyncEngine.isManagedCopy(at: copiedDir))
            XCTAssertTrue(fm.fileExists(atPath: copiedDir.appendingPathComponent("plugin.json").path))
        }

        // Scanners exclude managed copies from project-local skills and Vault auto-ingest
        XCTAssertTrue(SkillScannerService().scanProjectLocalSkills(projectPath: projectDir.path).isEmpty)
        XCTAssertTrue(PluginScannerService().autoIngestPlugins(
            from: projectDir.appendingPathComponent(".agents/plugins"),
            into: PathConstants.vaultPluginsDirectory
        ).isEmpty)

        // .git/info/exclude protects managed copies without touching .gitignore
        let gitignore = try String(contentsOf: projectDir.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertEqual(gitignore, "node_modules/\n")
        let gitExclude = try String(contentsOf: projectDir.appendingPathComponent(".git/info/exclude"), encoding: .utf8)
        XCTAssertTrue(gitExclude.contains(".agents/skills/a-skill"))
        XCTAssertTrue(gitExclude.contains(".agents/skills/z-skill"))
        XCTAssertTrue(gitExclude.contains(".agents/plugins/a-plugin"))
        XCTAssertTrue(gitExclude.contains(".agents/plugins/b-plugin"))
        XCTAssertFalse(gitExclude.contains(".agents/skills.json"))
        XCTAssertFalse(gitExclude.contains(".agents/plugins.json"))

        // Updating Vault SKILL.md propagates to managed copy on next sync
        let vaultSkillMd = PathConstants.vaultSkillsDirectory.appendingPathComponent("a-skill/SKILL.md")
        try "---\nname: a-skill\ndescription: Updated content\n---\n".write(to: vaultSkillMd, atomically: true, encoding: .utf8)
        try await syncEngine.syncProject(
            project: project,
            allServers: [],
            allSkills: [zSkill, aSkill],
            allPlugins: [bPlugin, aPlugin]
        )
        let syncedContent = try String(contentsOf: projectDir.appendingPathComponent(".agents/skills/a-skill/SKILL.md"), encoding: .utf8)
        XCTAssertTrue(syncedContent.contains("Updated content"))
    }

    func testPreservesUserManifestFieldsAndEntriesAcrossEnableDisablePurgeAndUninstall() async throws {
        let vaultSkill = try createVaultSkill(id: "vault-ops")
        let vaultPlugin = try createVaultPlugin(id: "vault-plug")
        let projectDir = try createGitRepoProject(named: "preserve-repo")
        let agentsDir = projectDir.appendingPathComponent(".agents", isDirectory: true)
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let teamSkillsManifest: [String: Any] = [
            "inherits": [["path": "/shared/team/skills.json", "include_only": ["shared-lint"]]],
            "exclude": ["experimental-.*"],
            "entries": [
                ["path": "tools/team-skills", "include_only": ["team-deploy"]],
                ["path": ".claude/skills"]
            ]
        ]
        try JSONSerialization.data(withJSONObject: teamSkillsManifest, options: [.prettyPrinted])
            .write(to: agentsDir.appendingPathComponent("skills.json"))

        let teamPluginsManifest: [String: Any] = [
            "exclude": ["legacy-plug"],
            "entries": [["path": "tools/team-plugins"]]
        ]
        try JSONSerialization.data(withJSONObject: teamPluginsManifest, options: [.prettyPrinted])
            .write(to: agentsDir.appendingPathComponent("plugins.json"))

        var project = ProjectProfile(
            id: "preserve-repo",
            name: "preserve-repo",
            path: projectDir.path,
            enabledSkillIds: ["vault-ops"],
            enabledPluginIds: ["vault-plug"]
        )

        let managedSkillDir = agentsDir.appendingPathComponent("skills/vault-ops", isDirectory: true)
        let managedPluginDir = agentsDir.appendingPathComponent("plugins/vault-plug", isDirectory: true)

        // 1. Enable Vault resources -> creates managed local copies while preserving team manifests untouched
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        XCTAssertTrue(SyncEngine.isManagedCopy(at: managedSkillDir))
        XCTAssertTrue(SyncEngine.isManagedCopy(at: managedPluginDir))
        let skillsAfterEnable = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        XCTAssertNotNil(skillsAfterEnable["inherits"])
        XCTAssertEqual(skillsAfterEnable["exclude"] as? [String], ["experimental-.*"])
        let enabledEntries = try XCTUnwrap(skillsAfterEnable["entries"] as? [[String: Any]])
        XCTAssertEqual(enabledEntries.count, 2)
        XCTAssertTrue(enabledEntries.contains { ($0["path"] as? String) == "tools/team-skills" && ($0["include_only"] as? [String]) == ["team-deploy"] })
        XCTAssertTrue(enabledEntries.contains { ($0["path"] as? String) == ".claude/skills" && $0["include_only"] == nil })
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy"])

        // 2. Disable Vault resources -> removes managed copies, preserves team entries & metadata
        project.enabledSkillIds = []
        project.enabledPluginIds = []
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        XCTAssertFalse(fm.fileExists(atPath: managedSkillDir.path))
        XCTAssertFalse(fm.fileExists(atPath: managedPluginDir.path))
        let skillsAfterDisable = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        let disabledEntries = try XCTUnwrap(skillsAfterDisable["entries"] as? [[String: Any]])
        XCTAssertEqual(disabledEntries.count, 2)
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy"])

        // 3. Re-enable and then purgeSkillCompletely / purgePluginCompletely -> removes managed copies & preserves team config
        project.enabledSkillIds = ["vault-ops"]
        project.enabledPluginIds = ["vault-plug"]
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])
        XCTAssertTrue(SyncEngine.isManagedCopy(at: managedSkillDir))
        XCTAssertTrue(SyncEngine.isManagedCopy(at: managedPluginDir))

        await syncEngine.purgeSkillCompletely(id: "vault-ops", allProjects: [project])
        await syncEngine.purgePluginCompletely(id: "vault-plug", allProjects: [project])

        XCTAssertFalse(fm.fileExists(atPath: managedSkillDir.path))
        XCTAssertFalse(fm.fileExists(atPath: managedPluginDir.path))
        let skillsAfterPurge = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy"])
        XCTAssertNotNil(skillsAfterPurge["inherits"])
        XCTAssertEqual(SyncEngine.readManifestPluginIds(at: projectDir), [])
        let pluginsAfterPurge = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("plugins.json"))) as? [String: Any])
        XCTAssertEqual(pluginsAfterPurge["exclude"] as? [String], ["legacy-plug"])

        // 4. Re-enable and run uninstallAndRestore -> removes managed copies, preserves team entries
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])
        _ = try await syncEngine.uninstallAndRestore(projects: [project], purgeVault: false)

        XCTAssertFalse(fm.fileExists(atPath: managedSkillDir.path))
        XCTAssertFalse(fm.fileExists(atPath: managedPluginDir.path))
        let skillsAfterUninstall = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        let uninstallEntries = try XCTUnwrap(skillsAfterUninstall["entries"] as? [[String: Any]])
        XCTAssertEqual(uninstallEntries.count, 2)
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy"])
    }

    func testPhysicalLocalSkillsAndPluginsAreNotOverwrittenAndLegacySymlinksAreReplaced() async throws {
        let vaultSkill = try createVaultSkill(id: "vault-only")
        let physicalSameIdSkill = try createVaultSkill(id: "local-override")
        let vaultPlugin = try createVaultPlugin(id: "vault-plug")
        let physicalPlugin = try createVaultPlugin(id: "local-plug")
        let projectDir = try createGitRepoProject(named: "physical-repo")

        // Create physical local skill + legacy symlinks (Vault symlink and stale .claude/skills symlink)
        let localSkillDir = projectDir.appendingPathComponent(".agents/skills/local-override", isDirectory: true)
        try fm.createDirectory(at: localSkillDir, withIntermediateDirectories: true)
        try "---\nname: local-override\ndescription: Custom local content\n---\n".write(to: localSkillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let legacyVaultSkillLink = projectDir.appendingPathComponent(".agents/skills/vault-only")
        try fm.createSymbolicLink(at: legacyVaultSkillLink, withDestinationURL: URL(fileURLWithPath: vaultSkill.path))

        let claudeLocalDir = projectDir.appendingPathComponent(".claude/skills/committed-skill", isDirectory: true)
        try fm.createDirectory(at: claudeLocalDir, withIntermediateDirectories: true)
        try "---\nname: committed-skill\n---\n".write(to: claudeLocalDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let brokenLegacyClaudeLink = projectDir.appendingPathComponent(".agents/skills/committed-skill")
        try fm.createSymbolicLink(at: brokenLegacyClaudeLink, withDestinationURL: URL(fileURLWithPath: "/nonexistent/Desktop/Projects/physical-repo/.claude/skills/committed-skill"))

        // Physical local plugin + legacy plugin symlink
        let localPluginDir = projectDir.appendingPathComponent(".agents/plugins/local-plug", isDirectory: true)
        try fm.createDirectory(at: localPluginDir, withIntermediateDirectories: true)
        try "{\"name\":\"local-plug-custom\"}\n".write(to: localPluginDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let legacyVaultPluginLink = projectDir.appendingPathComponent(".agents/plugins/vault-plug")
        try fm.createSymbolicLink(at: legacyVaultPluginLink, withDestinationURL: URL(fileURLWithPath: vaultPlugin.path))

        let project = ProjectProfile(
            id: "physical-repo",
            name: "physical-repo",
            path: projectDir.path,
            enabledSkillIds: ["vault-only", "local-override"],
            enabledPluginIds: ["vault-plug", "local-plug"]
        )

        try await syncEngine.syncProject(
            project: project,
            allServers: [],
            allSkills: [vaultSkill, physicalSameIdSkill],
            allPlugins: [vaultPlugin, physicalPlugin]
        )

        // Legacy symlinks replaced by managed copies (or removed for .claude/skills); physical directories untouched
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: legacyVaultSkillLink.path))
        XCTAssertTrue(SyncEngine.isManagedCopy(at: legacyVaultSkillLink))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: brokenLegacyClaudeLink.path))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: legacyVaultPluginLink.path))
        XCTAssertTrue(SyncEngine.isManagedCopy(at: legacyVaultPluginLink))

        XCTAssertFalse(SyncEngine.isManagedCopy(at: localSkillDir), "Physical local skill must never be overwritten with a managed copy")
        let localSkillText = try String(contentsOf: localSkillDir.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(localSkillText.contains("Custom local content"))

        XCTAssertFalse(SyncEngine.isManagedCopy(at: localPluginDir), "Physical local plugin must never be overwritten with a managed copy")
        let localPluginText = try String(contentsOf: localPluginDir.appendingPathComponent("plugin.json"), encoding: .utf8)
        XCTAssertTrue(localPluginText.contains("local-plug-custom"))

        // Committed .claude/skills skill remains referenced via relative in-workspace path in .agents/skills.json
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["committed-skill"])
        XCTAssertEqual(SyncEngine.readManifestPluginIds(at: projectDir), [])
    }

    func testIdempotencyAcrossSyncProjectAndLinkClaudeProjectSkills() async throws {
        let vaultSkill = try createVaultSkill(id: "hetzner-vps-ops")
        let projectDir = try createGitRepoProject(named: "idempotent-repo")
        let claudeLocal = projectDir.appendingPathComponent(".claude/skills/repo-local", isDirectory: true)
        try fm.createDirectory(at: claudeLocal, withIntermediateDirectories: true)
        try "---\nname: repo-local\n---\n".write(to: claudeLocal.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let project = ProjectProfile(
            id: "idempotent-repo",
            name: "idempotent-repo",
            path: projectDir.path,
            enabledSkillIds: ["hetzner-vps-ops"]
        )

        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [])

        let manifestURL = projectDir.appendingPathComponent(".agents/skills.json")
        let managedSkillMd = projectDir.appendingPathComponent(".agents/skills/hetzner-vps-ops/SKILL.md")
        let initialData = try Data(contentsOf: manifestURL)
        let fixedPast = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes([.modificationDate: fixedPast], ofItemAtPath: manifestURL.path)
        try fm.setAttributes([.modificationDate: fixedPast], ofItemAtPath: managedSkillMd.path)

        // Alternating syncProject and linkClaudeProjectSkills must not rewrite identical contents or re-copy unchanged skills
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [])
        await syncEngine.linkClaudeProjectSkills(project: project)
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [])

        let finalData = try Data(contentsOf: manifestURL)
        XCTAssertEqual(finalData, initialData)
        let finalMtime = (try fm.attributesOfItem(atPath: manifestURL.path)[.modificationDate] as? Date)
        XCTAssertEqual(finalMtime, fixedPast)
        let finalSkillMtime = (try fm.attributesOfItem(atPath: managedSkillMd.path)[.modificationDate] as? Date)
        XCTAssertEqual(finalSkillMtime, fixedPast)
    }

    @MainActor
    func testDiscoveryImportAndCLIBriefReadManagedCopies() async throws {
        let vaultSkill = try createVaultSkill(id: "hetzner-vps-ops")
        let vaultPlugin = try createVaultPlugin(id: "cloudflare")
        let projectDir = try createGitRepoProject(named: "discover-repo")
        let standaloneDir = sandbox.appendingPathComponent("ExternalImportRepo", isDirectory: true)
        try fm.createDirectory(at: standaloneDir, withIntermediateDirectories: true)

        let seededProj = ProjectProfile(
            id: "discover-repo",
            name: "discover-repo",
            path: projectDir.path,
            enabledSkillIds: ["hetzner-vps-ops"],
            enabledPluginIds: ["cloudflare"]
        )
        try await syncEngine.syncProject(project: seededProj, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        let standaloneProj = ProjectProfile(
            id: "ExternalImportRepo",
            name: "ExternalImportRepo",
            path: standaloneDir.path,
            enabledSkillIds: ["hetzner-vps-ops"],
            enabledPluginIds: ["cloudflare"]
        )
        try await syncEngine.syncProject(project: standaloneProj, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        // 1. ProjectScannerService reads managed copies
        let discovered = ProjectScannerService().discoverProjects()
        let found = try XCTUnwrap(discovered.first { $0.name == "discover-repo" })
        XCTAssertTrue(found.enabledSkillIds.contains("hetzner-vps-ops"))
        XCTAssertTrue(found.enabledPluginIds.contains("cloudflare"))

        // 2. AppState.registerProjectFolder reads managed copies
        let state = AppState(autoload: false)
        await state.registerProjectFolder(at: standaloneDir)
        let imported = try XCTUnwrap(state.projects.first { $0.name == "ExternalImportRepo" })
        XCTAssertTrue(imported.enabledSkillIds.contains("hetzner-vps-ops"))
        XCTAssertTrue(imported.enabledPluginIds.contains("cloudflare"))

        // 3. CLIRunner brief on unregistered directory reads managed copies
        let briefRes = await CLIRunner.execute(
            arguments: ["agymg", "brief", "--project", standaloneDir.path, "--json"]
        )
        XCTAssertEqual(briefRes.exitCode, 0)
        let brief = try JSONDecoder().decode(CLIBriefResponse.self, from: Data(briefRes.stdout.utf8))
        XCTAssertTrue(brief.active.projectSkills.contains { $0.id == "hetzner-vps-ops" })
        XCTAssertTrue(brief.active.projectPlugins.contains { $0.id == "cloudflare" })
    }

    func testUninstallRemovesManagedCopiesAndGitExcludeEntriesAndAuditDetectsCorruptManifest() async throws {
        let vaultSkill = try createVaultSkill(id: "vault-skill")
        let vaultPlugin = try createVaultPlugin(id: "vault-plugin")
        let projectDir = try createGitRepoProject(named: "cleanup-repo")

        let project = ProjectProfile(
            id: "cleanup-repo",
            name: "cleanup-repo",
            path: projectDir.path,
            enabledSkillIds: ["vault-skill"],
            enabledPluginIds: ["vault-plugin"]
        )

        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        let managedSkill = projectDir.appendingPathComponent(".agents/skills/vault-skill", isDirectory: true)
        let managedPlugin = projectDir.appendingPathComponent(".agents/plugins/vault-plugin", isDirectory: true)
        XCTAssertTrue(SyncEngine.isManagedCopy(at: managedSkill))
        XCTAssertTrue(SyncEngine.isManagedCopy(at: managedPlugin))

        // Corrupt skills.json -> ProjectAuditService must report .failed
        let skillsManifest = projectDir.appendingPathComponent(".agents/skills.json")
        try "{not valid json".write(to: skillsManifest, atomically: true, encoding: .utf8)
        let corruptAudit = ProjectAuditService().audit(project: project)
        XCTAssertEqual(corruptAudit.symlinkCheck.status, .failed)
        XCTAssertTrue(corruptAudit.symlinkCheck.detail.contains(".agents/skills.json"))

        // Remove corrupt manifest, re-sync cleanly, then uninstallAndRestore -> deletes managed copies & cleans .git/info/exclude
        try fm.removeItem(at: skillsManifest)
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])
        let validAudit = ProjectAuditService().audit(project: project)
        XCTAssertEqual(validAudit.symlinkCheck.status, .passed)

        let summary = try await syncEngine.uninstallAndRestore(projects: [project], purgeVault: false)
        XCTAssertFalse(fm.fileExists(atPath: managedSkill.path))
        XCTAssertFalse(fm.fileExists(atPath: managedPlugin.path))
        let removedResolved = Set(summary.removedProjectWrappers.map { SyncEngine.resolveEvenIfMissing(URL(fileURLWithPath: $0)) })
        XCTAssertTrue(removedResolved.contains(SyncEngine.resolveEvenIfMissing(managedSkill)))
        XCTAssertTrue(removedResolved.contains(SyncEngine.resolveEvenIfMissing(managedPlugin)))

        let gitExcludeAfter = try String(contentsOf: projectDir.appendingPathComponent(".git/info/exclude"), encoding: .utf8)
        XCTAssertFalse(gitExcludeAfter.contains(".agents/skills/vault-skill"))
        XCTAssertFalse(gitExcludeAfter.contains(".agents/plugins/vault-plugin"))
    }
}
