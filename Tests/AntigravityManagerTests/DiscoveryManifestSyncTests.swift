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

    func testManifestGenerationSortingCanonicalPathsAndGitExcludeWithoutTouchingGitignore() async throws {
        let zSkill = try createVaultSkill(id: "z-skill")
        let aSkill = try createVaultSkill(id: "a-skill")
        let bPlugin = try createVaultPlugin(id: "b-plugin")
        let aPlugin = try createVaultPlugin(id: "a-plugin")
        let projectDir = try createGitRepoProject(named: "manifest-repo")

        let project = ProjectProfile(
            id: "manifest-repo",
            name: "manifest-repo",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: ["z-skill", "a-skill"],
            enabledPluginIds: ["b-plugin", "a-plugin"]
        )

        try await syncEngine.syncProject(
            project: project,
            allServers: [],
            allSkills: [zSkill, aSkill],
            allPlugins: [bPlugin, aPlugin]
        )

        let skillsManifestURL = projectDir.appendingPathComponent(".agents/skills.json")
        let pluginsManifestURL = projectDir.appendingPathComponent(".agents/plugins.json")
        XCTAssertTrue(fm.fileExists(atPath: skillsManifestURL.path))
        XCTAssertTrue(fm.fileExists(atPath: pluginsManifestURL.path))

        let skillsRaw = try String(contentsOf: skillsManifestURL, encoding: .utf8)
        XCTAssertFalse(skillsRaw.contains("~"), "Manifest paths must never use ~")

        let skillsJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(skillsRaw.utf8)) as? [String: Any])
        let skillEntries = try XCTUnwrap(skillsJSON["entries"] as? [[String: Any]])
        XCTAssertEqual(skillEntries.count, 1)
        XCTAssertEqual(skillEntries.first?["path"] as? String, PathConstants.vaultSkillsDirectory.resolvingSymlinksInPath().path)
        XCTAssertEqual(skillEntries.first?["include_only"] as? [String], ["a-skill", "z-skill"])

        let pluginsJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pluginsManifestURL)) as? [String: Any])
        let pluginEntries = try XCTUnwrap(pluginsJSON["entries"] as? [[String: Any]])
        XCTAssertEqual(pluginEntries.count, 1)
        XCTAssertEqual(pluginEntries.first?["path"] as? String, PathConstants.vaultPluginsDirectory.resolvingSymlinksInPath().path)
        XCTAssertEqual(pluginEntries.first?["include_only"] as? [String], ["a-plugin", "b-plugin"])

        // .git/info/exclude protects manifests without touching .gitignore
        let gitignore = try String(contentsOf: projectDir.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertEqual(gitignore, "node_modules/\n")
        let gitExclude = try String(contentsOf: projectDir.appendingPathComponent(".git/info/exclude"), encoding: .utf8)
        XCTAssertTrue(gitExclude.contains(".agents/skills.json"))
        XCTAssertTrue(gitExclude.contains(".agents/plugins.json"))
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

        // 1. Enable Vault resources -> merges cleanly alongside team config
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        let skillsAfterEnable = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        XCTAssertNotNil(skillsAfterEnable["inherits"])
        XCTAssertEqual(skillsAfterEnable["exclude"] as? [String], ["experimental-.*"])
        let enabledEntries = try XCTUnwrap(skillsAfterEnable["entries"] as? [[String: Any]])
        XCTAssertEqual(enabledEntries.count, 3)
        XCTAssertTrue(enabledEntries.contains { ($0["path"] as? String) == "tools/team-skills" && ($0["include_only"] as? [String]) == ["team-deploy"] })
        XCTAssertTrue(enabledEntries.contains { ($0["path"] as? String) == ".claude/skills" && $0["include_only"] == nil })
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy", "vault-ops"])

        // 2. Disable Vault resources -> removes only Vault entries, keeps user entries & metadata
        project.enabledSkillIds = []
        project.enabledPluginIds = []
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        let skillsAfterDisable = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        let disabledEntries = try XCTUnwrap(skillsAfterDisable["entries"] as? [[String: Any]])
        XCTAssertEqual(disabledEntries.count, 2)
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy"])

        // 3. Re-enable and then purgeSkillCompletely / purgePluginCompletely -> preserves team config
        project.enabledSkillIds = ["vault-ops"]
        project.enabledPluginIds = ["vault-plug"]
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])

        await syncEngine.purgeSkillCompletely(id: "vault-ops", allProjects: [project])
        await syncEngine.purgePluginCompletely(id: "vault-plug", allProjects: [project])

        let skillsAfterPurge = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy"])
        XCTAssertNotNil(skillsAfterPurge["inherits"])
        XCTAssertEqual(SyncEngine.readManifestPluginIds(at: projectDir), [])
        let pluginsAfterPurge = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("plugins.json"))) as? [String: Any])
        XCTAssertEqual(pluginsAfterPurge["exclude"] as? [String], ["legacy-plug"])

        // 4. Re-enable and run uninstallAndRestore -> removes Vault entries, preserves team entries
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])
        _ = try await syncEngine.uninstallAndRestore(projects: [project], purgeVault: false)

        let skillsAfterUninstall = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: agentsDir.appendingPathComponent("skills.json"))) as? [String: Any])
        let uninstallEntries = try XCTUnwrap(skillsAfterUninstall["entries"] as? [[String: Any]])
        XCTAssertEqual(uninstallEntries.count, 2)
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["team-deploy"])
    }

    func testPhysicalLocalSkillsAndPluginsAreNotDuplicatedAndLegacySymlinksAreRemoved() async throws {
        let vaultSkill = try createVaultSkill(id: "vault-only")
        let physicalSameIdSkill = try createVaultSkill(id: "local-override")
        let vaultPlugin = try createVaultPlugin(id: "vault-plug")
        let physicalPlugin = try createVaultPlugin(id: "local-plug")
        let projectDir = try createGitRepoProject(named: "physical-repo")

        // Create physical local skill + legacy symlinks (Vault symlink and stale .claude/skills symlink)
        let localSkillDir = projectDir.appendingPathComponent(".agents/skills/local-override", isDirectory: true)
        try fm.createDirectory(at: localSkillDir, withIntermediateDirectories: true)
        try "---\nname: local-override\n---\n".write(to: localSkillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let legacyVaultSkillLink = projectDir.appendingPathComponent(".agents/skills/vault-only")
        try fm.createSymbolicLink(at: legacyVaultSkillLink, withDestinationURL: URL(fileURLWithPath: vaultSkill.path))

        let claudeLocalDir = projectDir.appendingPathComponent(".claude/skills/committed-skill", isDirectory: true)
        try fm.createDirectory(at: claudeLocalDir, withIntermediateDirectories: true)
        try "---\nname: committed-skill\n---\n".write(to: claudeLocalDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let brokenLegacyClaudeLink = projectDir.appendingPathComponent(".agents/skills/committed-skill")
        try fm.createSymbolicLink(at: brokenLegacyClaudeLink, withDestinationURL: URL(fileURLWithPath: "/nonexistent/Desktop/Projects/physical-repo/.claude/skills/committed-skill"))

        // Physical local plugin + agy-manager + legacy plugin symlink
        let localPluginDir = projectDir.appendingPathComponent(".agents/plugins/local-plug", isDirectory: true)
        try fm.createDirectory(at: localPluginDir, withIntermediateDirectories: true)
        try "{\"name\":\"local-plug\"}\n".write(to: localPluginDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

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

        // Legacy symlinks removed, physical directories untouched
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: legacyVaultSkillLink.path))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: brokenLegacyClaudeLink.path))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: legacyVaultPluginLink.path))
        XCTAssertTrue(fm.fileExists(atPath: localSkillDir.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: localPluginDir.appendingPathComponent("plugin.json").path))

        // Physical local skill/plugin NOT duplicated into manifests, while committed .claude/skills skill IS included
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectDir), ["committed-skill", "vault-only"])
        XCTAssertEqual(SyncEngine.readManifestPluginIds(at: projectDir), ["vault-plug"])
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
        let initialData = try Data(contentsOf: manifestURL)
        let fixedPast = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes([.modificationDate: fixedPast], ofItemAtPath: manifestURL.path)

        // Alternating syncProject and linkClaudeProjectSkills must not rewrite identical contents
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [])
        await syncEngine.linkClaudeProjectSkills(project: project)
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [])

        let finalData = try Data(contentsOf: manifestURL)
        XCTAssertEqual(finalData, initialData)
        let finalMtime = (try fm.attributesOfItem(atPath: manifestURL.path)[.modificationDate] as? Date)
        XCTAssertEqual(finalMtime, fixedPast)
    }

    @MainActor
    func testDiscoveryImportAndCLIBriefReadManifests() async throws {
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

        // 1. ProjectScannerService reads manifests
        let discovered = ProjectScannerService().discoverProjects()
        let found = try XCTUnwrap(discovered.first { $0.name == "discover-repo" })
        XCTAssertTrue(found.enabledSkillIds.contains("hetzner-vps-ops"))
        XCTAssertTrue(found.enabledPluginIds.contains("cloudflare"))

        // 2. AppState.registerProjectFolder reads manifests
        let state = AppState(autoload: false)
        await state.registerProjectFolder(at: standaloneDir)
        let imported = try XCTUnwrap(state.projects.first { $0.name == "ExternalImportRepo" })
        XCTAssertTrue(imported.enabledSkillIds.contains("hetzner-vps-ops"))
        XCTAssertTrue(imported.enabledPluginIds.contains("cloudflare"))

        // 3. CLIRunner brief on unregistered directory reads manifests
        let briefRes = await CLIRunner.execute(
            arguments: ["agymg", "brief", "--project", standaloneDir.path, "--json"]
        )
        XCTAssertEqual(briefRes.exitCode, 0)
        let brief = try JSONDecoder().decode(CLIBriefResponse.self, from: Data(briefRes.stdout.utf8))
        XCTAssertTrue(brief.active.projectSkills.contains { $0.id == "hetzner-vps-ops" })
        XCTAssertTrue(brief.active.projectPlugins.contains { $0.id == "cloudflare" })
    }

    func testUninstallRemovesEmptyManifestsAndGitExcludeEntriesAndAuditDetectsCorruptManifest() async throws {
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

        let skillsManifest = projectDir.appendingPathComponent(".agents/skills.json")
        let pluginsManifest = projectDir.appendingPathComponent(".agents/plugins.json")
        XCTAssertTrue(fm.fileExists(atPath: skillsManifest.path))
        XCTAssertTrue(fm.fileExists(atPath: pluginsManifest.path))

        // Corrupt skills.json -> ProjectAuditService must report .failed
        try "{not valid json".write(to: skillsManifest, atomically: true, encoding: .utf8)
        let corruptAudit = ProjectAuditService().audit(project: project)
        XCTAssertEqual(corruptAudit.symlinkCheck.status, .failed)
        XCTAssertTrue(corruptAudit.symlinkCheck.detail.contains(".agents/skills.json"))

        // Re-sync cleanly, then uninstallAndRestore -> deletes manifests & cleans .git/info/exclude
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [vaultSkill], allPlugins: [vaultPlugin])
        let validAudit = ProjectAuditService().audit(project: project)
        XCTAssertEqual(validAudit.symlinkCheck.status, .passed)

        let summary = try await syncEngine.uninstallAndRestore(projects: [project], purgeVault: false)
        XCTAssertFalse(fm.fileExists(atPath: skillsManifest.path))
        XCTAssertFalse(fm.fileExists(atPath: pluginsManifest.path))
        XCTAssertTrue(summary.removedProjectWrappers.contains(skillsManifest.path))
        XCTAssertTrue(summary.removedProjectWrappers.contains(pluginsManifest.path))

        let gitExcludeAfter = try String(contentsOf: projectDir.appendingPathComponent(".git/info/exclude"), encoding: .utf8)
        XCTAssertFalse(gitExcludeAfter.contains(".agents/skills.json"))
        XCTAssertFalse(gitExcludeAfter.contains(".agents/plugins.json"))
    }
}
