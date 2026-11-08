import XCTest
@testable import AntigravityManager

@MainActor
final class M4ChallengerAdversarialTests: XCTestCase {
    private var testSandboxDir: URL!
    private let fm = FileManager.default
    private var syncEngine: SyncEngine!
    private var state: AppState!

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("M4Challenger_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        testSandboxDir = dir
        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()

        syncEngine = SyncEngine()
        state = AppState()
    }

    override func tearDown() async throws {
        syncEngine = nil
        state = nil
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let dir = testSandboxDir {
            try? fm.removeItem(at: dir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        try await super.tearDown()
    }

    // MARK: - 1. Deep Hierarchy & Metadata Plugin Ingestion
    func testPluginAutoIngestDeepHierarchyAndMetadata() throws {
        let scanner = PluginScannerService()

        // Create global plugin with nested hierarchy:
        // custom-deep-plugin/
        //   ├── plugin.json
        //   ├── mcp_config.json
        //   ├── skills/
        //   │   └── nested-skill/
        //   │       └── SKILL.md
        //   └── submodules/
        //       └── helper.js
        let globalDir = PathConstants.globalPluginsDirectory.appendingPathComponent("custom-deep-plugin", isDirectory: true)
        try fm.createDirectory(at: globalDir.appendingPathComponent("skills/nested-skill", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: globalDir.appendingPathComponent("submodules", isDirectory: true), withIntermediateDirectories: true)

        let meta = ["name": "Custom Deep Plugin", "description": "Deep nested plugin bundle test"]
        let metaData = try JSONSerialization.data(withJSONObject: meta)
        try metaData.write(to: globalDir.appendingPathComponent("plugin.json"))

        let mcp = ["mcpServers": ["deep-mcp": ["command": "node"]]]
        let mcpData = try JSONSerialization.data(withJSONObject: mcp)
        try mcpData.write(to: globalDir.appendingPathComponent("mcp_config.json"))

        try "--- name: Nested Skill ---".write(to: globalDir.appendingPathComponent("skills/nested-skill/SKILL.md"), atomically: true, encoding: .utf8)
        try "console.log('deep helper');".write(to: globalDir.appendingPathComponent("submodules/helper.js"), atomically: true, encoding: .utf8)

        // Execute scanVaultPlugins which triggers autoIngestPlugins
        let plugins = scanner.scanVaultPlugins()

        let vaultPlugin = plugins.first(where: { $0.id == "custom-deep-plugin" })
        XCTAssertNotNil(vaultPlugin, "Deep plugin should be discovered and ingested into vault")
        XCTAssertEqual(vaultPlugin?.name, "Custom Deep Plugin")
        XCTAssertEqual(vaultPlugin?.description, "Deep nested plugin bundle test")
        XCTAssertEqual(vaultPlugin?.hasMCP, true)
        XCTAssertEqual(vaultPlugin?.hasSkills, true)

        // Verify deep files copied to vault
        let vaultPluginURL = PathConstants.vaultPluginsDirectory.appendingPathComponent("custom-deep-plugin")
        XCTAssertTrue(fm.fileExists(atPath: vaultPluginURL.appendingPathComponent("skills/nested-skill/SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: vaultPluginURL.appendingPathComponent("submodules/helper.js").path))

        let copiedHelper = try String(contentsOf: vaultPluginURL.appendingPathComponent("submodules/helper.js"), encoding: .utf8)
        XCTAssertEqual(copiedHelper, "console.log('deep helper');", "Deep hierarchy file content must match verbatim")
    }

    // MARK: - 2. Ingestion Exclusions & Symlink Skipping
    func testPluginAutoIngestExclusionsAndSymlinkSkipping() throws {
        let scanner = PluginScannerService()

        let projectDir = testSandboxDir.appendingPathComponent("Projects/AdversarialProj", isDirectory: true)
        let pluginsDir = projectDir.appendingPathComponent(".agents/plugins", isDirectory: true)
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

        // a) agy-manager plugin (MUST BE SKIPPED)
        let agyDir = pluginsDir.appendingPathComponent("agy-manager", isDirectory: true)
        try fm.createDirectory(at: agyDir, withIntermediateDirectories: true)
        try "{}".write(to: agyDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        // b) Symlinked plugin (MUST BE SKIPPED)
        let externalTarget = testSandboxDir.appendingPathComponent("ExternalPlugin", isDirectory: true)
        try fm.createDirectory(at: externalTarget, withIntermediateDirectories: true)
        try "{}".write(to: externalTarget.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        let symlinkPlugin = pluginsDir.appendingPathComponent("symlinked-plugin")
        try fm.createSymbolicLink(at: symlinkPlugin, withDestinationURL: externalTarget)

        // c) Regular non-directory file (MUST BE SKIPPED)
        let strayFile = pluginsDir.appendingPathComponent("stray-plugin.json")
        try "{}".write(to: strayFile, atomically: true, encoding: .utf8)

        // d) Hidden directory (MUST BE SKIPPED)
        let hiddenDir = pluginsDir.appendingPathComponent(".hidden-plugin", isDirectory: true)
        try fm.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try "{}".write(to: hiddenDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        // e) Genuine physical plugin (MUST BE INGESTED)
        let genuineDir = pluginsDir.appendingPathComponent("genuine-plugin", isDirectory: true)
        try fm.createDirectory(at: genuineDir, withIntermediateDirectories: true)
        try "{}".write(to: genuineDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let project = ProjectProfile(
            id: "adv-proj",
            name: "AdversarialProj",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: []
        )

        let scanned = scanner.scanAllPlugins(projects: [project])
        let scannedIds = Set(scanned.map(\.id))

        // Assertions
        XCTAssertTrue(scannedIds.contains("genuine-plugin"), "Genuine plugin must be ingested")
        XCTAssertFalse(scannedIds.contains("agy-manager"), "agy-manager must NEVER be ingested into vault")
        XCTAssertFalse(fm.fileExists(atPath: PathConstants.vaultPluginsDirectory.appendingPathComponent("agy-manager").path))
        XCTAssertFalse(fm.fileExists(atPath: PathConstants.vaultPluginsDirectory.appendingPathComponent("symlinked-plugin").path), "Symlinked plugins must not be copied to vault")
        XCTAssertFalse(fm.fileExists(atPath: PathConstants.vaultPluginsDirectory.appendingPathComponent("stray-plugin.json").path))
        XCTAssertFalse(fm.fileExists(atPath: PathConstants.vaultPluginsDirectory.appendingPathComponent(".hidden-plugin").path))
    }

    // MARK: - 3. Non-Overwriting Protection
    func testPluginAutoIngestNeverOverwritesExistingVaultPlugin() throws {
        let scanner = PluginScannerService()

        // Pre-create canonical vault plugin
        let vaultPlugin = PathConstants.vaultPluginsDirectory.appendingPathComponent("immutable-plugin", isDirectory: true)
        try fm.createDirectory(at: vaultPlugin, withIntermediateDirectories: true)
        let canonicalFile = vaultPlugin.appendingPathComponent("version.txt")
        try "VAULT_CANONICAL_V1".write(to: canonicalFile, atomically: true, encoding: .utf8)

        // Project has plugin with the same ID but conflicting contents
        let projectDir = testSandboxDir.appendingPathComponent("Projects/ConflictProj", isDirectory: true)
        let pluginsDir = projectDir.appendingPathComponent(".agents/plugins/immutable-plugin", isDirectory: true)
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let conflictFile = pluginsDir.appendingPathComponent("version.txt")
        try "PROJECT_CONFLICT_V2".write(to: conflictFile, atomically: true, encoding: .utf8)

        let project = ProjectProfile(
            id: "conflict-proj",
            name: "ConflictProj",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: []
        )

        _ = scanner.scanAllPlugins(projects: [project])

        // Verify Vault version is intact
        let vaultContent = try String(contentsOf: canonicalFile, encoding: .utf8)
        XCTAssertEqual(vaultContent, "VAULT_CANONICAL_V1", "Vault plugin MUST NEVER be overwritten by project copy")
    }

    // MARK: - 4. Broken Symlink Resilience in Vault
    func testPluginAutoIngestResilientToBrokenSymlinkInVault() throws {
        let scanner = PluginScannerService()
        try fm.createDirectory(at: PathConstants.vaultPluginsDirectory, withIntermediateDirectories: true)

        // Create a broken symlink in Vault pointing to non-existent location
        let brokenVaultSymlink = PathConstants.vaultPluginsDirectory.appendingPathComponent("broken-plugin")
        let nonExistentTarget = testSandboxDir.appendingPathComponent("DoesNotExist")
        try fm.createSymbolicLink(at: brokenVaultSymlink, withDestinationURL: nonExistentTarget)

        // Project has a plugin with the same ID
        let projectDir = testSandboxDir.appendingPathComponent("Projects/BrokenSymlinkProj", isDirectory: true)
        let projectPlugin = projectDir.appendingPathComponent(".agents/plugins/broken-plugin", isDirectory: true)
        try fm.createDirectory(at: projectPlugin, withIntermediateDirectories: true)
        try "{}".write(to: projectPlugin.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let project = ProjectProfile(
            id: "broken-proj",
            name: "BrokenSymlinkProj",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: []
        )

        // autoIngestPlugins should detect destExists (handling broken symlink) without crashing
        _ = scanner.scanAllPlugins(projects: [project])
        let ingested = scanner.autoIngestPlugins(
            from: projectDir.appendingPathComponent(".agents/plugins"),
            into: PathConstants.vaultPluginsDirectory
        )

        XCTAssertFalse(ingested.contains("broken-plugin"), "Should not attempt to overwrite broken symlink or crash")
    }

    // MARK: - 5. Safe Copy-Before-Remove Zero Data Loss
    func testProjectPluginSafeCopyBeforeRemoveFullCycle() async throws {
        let projectDir = testSandboxDir.appendingPathComponent("Projects/SafeCycleProj", isDirectory: true)
        let pluginsDir = projectDir.appendingPathComponent(".agents/plugins", isDirectory: true)
        let customPluginDir = pluginsDir.appendingPathComponent("user-authored-plugin", isDirectory: true)
        let nestedDir = customPluginDir.appendingPathComponent("config/keys", isDirectory: true)
        try fm.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let payloadData = "SUPER_SECRET_PAYLOAD_ABC123".data(using: .utf8)!
        try payloadData.write(to: nestedDir.appendingPathComponent("apiKey.txt"))
        try "{\"name\":\"User Authored\"}".write(to: customPluginDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let project = ProjectProfile(
            id: "safe-cycle",
            name: "SafeCycleProj",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: [] // DISABLED
        )

        let pluginDef = PluginDefinition(
            id: "user-authored-plugin",
            name: "User Authored",
            description: "Test",
            path: customPluginDir.path
        )

        // SYNC 1: Disabled -> Safe non-destructive copy to Vault; physical project directory MUST NOT be deleted (P1 #4)
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [], allPlugins: [pluginDef])

        XCTAssertTrue(fm.fileExists(atPath: customPluginDir.path), "Physical project plugin directory must never be deleted (P1 #4)")

        // Verify vault has complete copy with nested files
        let vaultPluginDir = PathConstants.vaultPluginsDirectory.appendingPathComponent("user-authored-plugin")
        XCTAssertTrue(fm.fileExists(atPath: vaultPluginDir.path), "Vault must preserve the plugin")
        let restoredKey = try String(contentsOf: vaultPluginDir.appendingPathComponent("config/keys/apiKey.txt"), encoding: .utf8)
        XCTAssertEqual(restoredKey, "SUPER_SECRET_PAYLOAD_ABC123", "Nested file content must be preserved without data loss")

        // SYNC 2: Enable on a consumer project -> creates symlink pointing to Vault
        let consumerDir = testSandboxDir.appendingPathComponent("Projects/ConsumerCycleProj", isDirectory: true)
        try fm.createDirectory(at: consumerDir, withIntermediateDirectories: true)
        let consumerPluginTarget = consumerDir.appendingPathComponent(".agents/plugins/user-authored-plugin")
        var consumerProject = ProjectProfile(
            id: "consumer-cycle",
            name: "ConsumerCycleProj",
            path: consumerDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: ["user-authored-plugin"]
        )
        let vaultBackedDef = PluginDefinition(
            id: "user-authored-plugin",
            name: "User Authored",
            description: "Test",
            path: vaultPluginDir.path
        )
        try await syncEngine.syncProject(project: consumerProject, allServers: [], allSkills: [], allPlugins: [vaultBackedDef])

        XCTAssertTrue(fm.fileExists(atPath: consumerPluginTarget.path), "Enabled plugin symlink must exist")
        let isSymlink = await syncEngine.isSymlink(at: consumerPluginTarget)
        XCTAssertTrue(isSymlink, "Enabled plugin must be a symlink")
        let resolved = consumerPluginTarget.resolvingSymlinksInPath().path
        XCTAssertEqual(resolved, vaultPluginDir.resolvingSymlinksInPath().path)

        // Reading through the symlink works
        let readFromSymlink = try String(contentsOf: consumerPluginTarget.appendingPathComponent("config/keys/apiKey.txt"), encoding: .utf8)
        XCTAssertEqual(readFromSymlink, "SUPER_SECRET_PAYLOAD_ABC123")

        // SYNC 3: Disable again -> Symlink is safely removed, Vault copy and original physical folder remain intact
        consumerProject.enabledPluginIds.remove("user-authored-plugin")
        try await syncEngine.syncProject(project: consumerProject, allServers: [], allSkills: [], allPlugins: [vaultBackedDef])

        XCTAssertFalse(fm.fileExists(atPath: consumerPluginTarget.path), "Symlink must be removed")
        XCTAssertTrue(fm.fileExists(atPath: customPluginDir.path), "Original physical folder MUST remain intact")
        XCTAssertTrue(fm.fileExists(atPath: vaultPluginDir.path), "Vault copy MUST remain intact")
        let stillIntact = try String(contentsOf: vaultPluginDir.appendingPathComponent("config/keys/apiKey.txt"), encoding: .utf8)
        XCTAssertEqual(stillIntact, "SUPER_SECRET_PAYLOAD_ABC123")
    }

    // MARK: - 6. Skill Scanner Symlink Exclusion & Broken Symlink Resilience
    func testSkillScannerExcludesSymlinksAndBrokenSymlinks() throws {
        let scanner = SkillScannerService()

        let projectDir = testSandboxDir.appendingPathComponent("Projects/SkillStressProj", isDirectory: true)
        let skillsDir = projectDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        // 1. Physical local skills
        let physical1 = skillsDir.appendingPathComponent("local-swift-helper", isDirectory: true)
        try fm.createDirectory(at: physical1, withIntermediateDirectories: true)
        try "---\nname: Swift Helper\ndescription: Local swift helper\n---".write(to: physical1.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let physical2 = skillsDir.appendingPathComponent("local-db-migration", isDirectory: true)
        try fm.createDirectory(at: physical2, withIntermediateDirectories: true)
        try "---\nname: DB Migration\ndescription: Local db migration\n---".write(to: physical2.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // 2. Symlink to Vault skill
        let vaultSkill = PathConstants.vaultSkillsDirectory.appendingPathComponent("vault-react", isDirectory: true)
        try fm.createDirectory(at: vaultSkill, withIntermediateDirectories: true)
        try "---\nname: Vault React\ndescription: React skill in vault\n---".write(to: vaultSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let symlinkVault = skillsDir.appendingPathComponent("vault-react")
        try fm.createSymbolicLink(at: symlinkVault, withDestinationURL: vaultSkill)

        // 3. Symlink to Global skill
        let globalSkill = PathConstants.globalSkillsDirectory.appendingPathComponent("global-ask", isDirectory: true)
        try fm.createDirectory(at: globalSkill, withIntermediateDirectories: true)
        try "---\nname: Global Ask\ndescription: Ask skill in global\n---".write(to: globalSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let symlinkGlobal = skillsDir.appendingPathComponent("global-ask")
        try fm.createSymbolicLink(at: symlinkGlobal, withDestinationURL: globalSkill)

        // 4. Broken symlink
        let brokenSymlink = skillsDir.appendingPathComponent("broken-skill")
        let nonExistent = testSandboxDir.appendingPathComponent("MissingSkillDir")
        try fm.createSymbolicLink(at: brokenSymlink, withDestinationURL: nonExistent)

        // Run scanProjectLocalSkills
        let scannedLocals = scanner.scanProjectLocalSkills(projectPath: projectDir.path)
        let scannedIds = Set(scannedLocals.map(\.id))

        // Assertions: exactly physical1 and physical2 are returned
        XCTAssertEqual(scannedLocals.count, 2, "Only physical local skills must be returned")
        XCTAssertTrue(scannedIds.contains("local-swift-helper"))
        XCTAssertTrue(scannedIds.contains("local-db-migration"))
        XCTAssertFalse(scannedIds.contains("vault-react"), "Symlink to vault skill must be excluded")
        XCTAssertFalse(scannedIds.contains("global-ask"), "Symlink to global skill must be excluded")
        XCTAssertFalse(scannedIds.contains("broken-skill"), "Broken symlink must be excluded")
    }

    // MARK: - 7. Skill Deduplication Set Union Empirical Accuracy
    func testSkillDeduplicationFormulaOverlappingSets() {
        // Scenario:
        // Local skills physically present on disk: ["local-alpha", "shared-beta"]
        // Enabled skill IDs stored in project profile: ["shared-beta", "vault-gamma", "vault-delta"]
        //
        // "shared-beta" is present in BOTH local directory and enabledSkillIds.
        // Total unique skills available/enabled in this project MUST be 4:
        // ["local-alpha", "shared-beta", "vault-gamma", "vault-delta"]
        //
        // Naive addition (locals.count + enabled.count) would yield 2 + 3 = 5 (BUG).
        // Deduplicated union yields 4 (CORRECT).

        let localSkills = [
            SkillDefinition(id: "local-alpha", name: "Alpha", description: "Alpha", category: "Core", path: "/path/alpha", origin: .projectLocal),
            SkillDefinition(id: "shared-beta", name: "Beta", description: "Beta", category: "Core", path: "/path/beta", origin: .projectLocal)
        ]

        let enabledSkillIds: Set<String> = ["shared-beta", "vault-gamma", "vault-delta"]

        let localIds = Set(localSkills.map(\.id))
        let totalCount = localIds.union(enabledSkillIds).count

        XCTAssertEqual(totalCount, 4, "Set union must collapse duplicate IDs to exactly 4 distinct skills")
        XCTAssertEqual(localIds.union(enabledSkillIds), Set(["local-alpha", "shared-beta", "vault-gamma", "vault-delta"]))
    }

    // MARK: - 8. ProjectSkillsTab Deduplication Logic
    func testProjectSkillsTabDeduplicationFiltersOutVaultIds() {
        // If a local skill has an ID that also exists in state.skills (Vault),
        // ProjectSkillsTab.projectLocals filters it out so it never appears in both
        // "Local in Repository" and "Master Vault Catalog".

        let localSkills = [
            SkillDefinition(id: "only-local", name: "Only Local", description: "", category: "Core", path: "/path/1", origin: .projectLocal),
            SkillDefinition(id: "vault-and-local", name: "Duplicate Name", description: "", category: "Core", path: "/path/2", origin: .projectLocal)
        ]

        let vaultSkills = [
            SkillDefinition(id: "vault-and-local", name: "Vault Version", description: "", category: "Core", path: "/vault/2", origin: .vault),
            SkillDefinition(id: "vault-only", name: "Vault Only", description: "", category: "Core", path: "/vault/3", origin: .vault)
        ]

        let vaultIds = Set(vaultSkills.map(\.id))
        let projectLocals = localSkills.filter { !vaultIds.contains($0.id) }

        XCTAssertEqual(projectLocals.count, 1)
        XCTAssertEqual(projectLocals.first?.id, "only-local")

        // Category counts deduplication
        var seen = Set<String>()
        let allSkills = (projectLocals + vaultSkills).filter { seen.insert($0.id).inserted }
        XCTAssertEqual(allSkills.count, 3, "Total distinct skills across both categories must be 3")
        XCTAssertEqual(Set(allSkills.map(\.id)), Set(["only-local", "vault-and-local", "vault-only"]))
    }
}
