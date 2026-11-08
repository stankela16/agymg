import XCTest
@testable import AntigravityManager

@MainActor
final class M4VaultAndSyncCompletenessTests: XCTestCase {
    private var testSandboxDir: URL!
    private let fm = FileManager.default
    private var syncEngine: SyncEngine!
    private var state: AppState!

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("M4Tests_\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - 1. VaultService Directory Initialization
    func testVaultServiceInitializesPluginsAndSkillsDirectories() async throws {
        let vaultService = VaultService()
        await vaultService.initializeVaultIfNeeded()

        XCTAssertTrue(fm.fileExists(atPath: PathConstants.vaultDirectory.path), "Vault directory should exist")
        XCTAssertTrue(fm.fileExists(atPath: PathConstants.vaultPluginsDirectory.path), "Vault plugins directory should exist")
        XCTAssertTrue(fm.fileExists(atPath: PathConstants.vaultSkillsDirectory.path), "Vault skills directory should exist")
    }

    // MARK: - 2. Plugin Auto-Ingest from Global and Project Directories
    func testPluginAutoIngestionFromGlobalAndProjectWithoutOverwriting() throws {
        let scanner = PluginScannerService()

        // 1. Create a global plugin
        let globalPluginDir = PathConstants.globalPluginsDirectory.appendingPathComponent("custom-global-plugin", isDirectory: true)
        try fm.createDirectory(at: globalPluginDir, withIntermediateDirectories: true)
        let globalJson = try JSONSerialization.data(withJSONObject: ["name": "Custom Global", "description": "Global plugin test"])
        try globalJson.write(to: globalPluginDir.appendingPathComponent("plugin.json"))

        // 2. Create a project with a project-local plugin and agy-manager plugin
        let projectDir = testSandboxDir.appendingPathComponent("Projects/TestProject", isDirectory: true)
        let projectPluginsDir = projectDir.appendingPathComponent(".agents/plugins", isDirectory: true)
        let customProjectPluginDir = projectPluginsDir.appendingPathComponent("custom-project-plugin", isDirectory: true)
        try fm.createDirectory(at: customProjectPluginDir, withIntermediateDirectories: true)
        let projJson = try JSONSerialization.data(withJSONObject: ["name": "Custom Project", "description": "Project plugin test"])
        try projJson.write(to: customProjectPluginDir.appendingPathComponent("plugin.json"))
        let mcpJson = try JSONSerialization.data(withJSONObject: ["mcpServers": [:]])
        try mcpJson.write(to: customProjectPluginDir.appendingPathComponent("mcp_config.json"))

        // agy-manager should be excluded from auto-ingest
        let agyManagerDir = projectPluginsDir.appendingPathComponent("agy-manager", isDirectory: true)
        try fm.createDirectory(at: agyManagerDir, withIntermediateDirectories: true)
        try projJson.write(to: agyManagerDir.appendingPathComponent("plugin.json"))

        // 3. Pre-create a vault plugin to test non-overwriting
        let vaultPluginDir = PathConstants.vaultPluginsDirectory.appendingPathComponent("existing-plugin", isDirectory: true)
        try fm.createDirectory(at: vaultPluginDir, withIntermediateDirectories: true)
        let originalMarker = vaultPluginDir.appendingPathComponent("marker.txt")
        try "ORIGINAL_VAULT_CONTENT".write(to: originalMarker, atomically: true, encoding: .utf8)

        // Same ID in project with different content
        let conflictProjectPlugin = projectPluginsDir.appendingPathComponent("existing-plugin", isDirectory: true)
        try fm.createDirectory(at: conflictProjectPlugin, withIntermediateDirectories: true)
        try "CONFLICT_PROJECT_CONTENT".write(to: conflictProjectPlugin.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let project = ProjectProfile(
            id: "test-proj",
            name: "TestProject",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: []
        )

        // Perform scan & auto-ingestion
        let allPlugins = scanner.scanAllPlugins(projects: [project])

        // Verify custom-global-plugin ingested to vault
        let ingestedGlobal = PathConstants.vaultPluginsDirectory.appendingPathComponent("custom-global-plugin")
        XCTAssertTrue(fm.fileExists(atPath: ingestedGlobal.path), "Global plugin should be auto-ingested into Master Vault")

        // Verify custom-project-plugin ingested to vault
        let ingestedProject = PathConstants.vaultPluginsDirectory.appendingPathComponent("custom-project-plugin")
        XCTAssertTrue(fm.fileExists(atPath: ingestedProject.path), "Project plugin should be auto-ingested into Master Vault")
        XCTAssertTrue(fm.fileExists(atPath: ingestedProject.appendingPathComponent("mcp_config.json").path))

        // Verify agy-manager was excluded from vault
        let ingestedAgyManager = PathConstants.vaultPluginsDirectory.appendingPathComponent("agy-manager")
        XCTAssertFalse(fm.fileExists(atPath: ingestedAgyManager.path), "agy-manager must NOT be ingested into Master Vault")

        // Verify non-overwriting of existing vault plugin
        let currentMarker = try String(contentsOf: originalMarker, encoding: .utf8)
        XCTAssertEqual(currentMarker, "ORIGINAL_VAULT_CONTENT", "Existing vault plugins must never be overwritten by project copies")

        // Verify scanAllPlugins returns all distinct plugins
        let pluginIds = allPlugins.map(\.id)
        XCTAssertTrue(pluginIds.contains("custom-global-plugin"))
        XCTAssertTrue(pluginIds.contains("custom-project-plugin"))
        XCTAssertTrue(pluginIds.contains("existing-plugin"))
        XCTAssertFalse(pluginIds.contains("agy-manager"))
    }

    // MARK: - 3. Project Plugin Safe Copy-Before-Remove
    func testProjectPluginSafeCopyBeforeRemoveWhenDisabled() async throws {
        let projectDir = testSandboxDir.appendingPathComponent("Projects/SafeSyncProject", isDirectory: true)
        let pluginsDir = projectDir.appendingPathComponent(".agents/plugins", isDirectory: true)
        let customPluginDir = pluginsDir.appendingPathComponent("safe-plugin", isDirectory: true)
        try fm.createDirectory(at: customPluginDir, withIntermediateDirectories: true)

        let pluginJson = try JSONSerialization.data(withJSONObject: ["name": "Safe Plugin", "description": "Safe copy test"])
        try pluginJson.write(to: customPluginDir.appendingPathComponent("plugin.json"))
        let secretData = "CONFIDENTIAL_KEY_XYZ".data(using: .utf8)!
        try secretData.write(to: customPluginDir.appendingPathComponent("secret.txt"))

        var project = ProjectProfile(
            id: "safe-proj",
            name: "SafeSyncProject",
            path: projectDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: [] // Disabled!
        )

        let pluginDef = PluginDefinition(
            id: "safe-plugin",
            name: "Safe Plugin",
            description: "Safe copy test",
            path: customPluginDir.path
        )

        // Sync with plugin disabled
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [], allPlugins: [pluginDef])

        // Verify that customPluginDir was removed from the project folder
        XCTAssertFalse(fm.fileExists(atPath: customPluginDir.path), "Disabled plugin should be removed from project plugins folder")

        // Verify that the plugin was safely backed up to Master Vault before deletion
        let vaultPluginDir = PathConstants.vaultPluginsDirectory.appendingPathComponent("safe-plugin")
        XCTAssertTrue(fm.fileExists(atPath: vaultPluginDir.path), "Disabled plugin must be preserved in Master Vault")
        let restoredSecret = try String(contentsOf: vaultPluginDir.appendingPathComponent("secret.txt"), encoding: .utf8)
        XCTAssertEqual(restoredSecret, "CONFIDENTIAL_KEY_XYZ")

        // Now re-enable the plugin
        project.enabledPluginIds.insert("safe-plugin")
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [], allPlugins: [pluginDef])

        // Verify that it is now a symlink pointing to Vault
        XCTAssertTrue(fm.fileExists(atPath: customPluginDir.path))
        let isSym = await syncEngine.isSymlink(at: customPluginDir)
        XCTAssertTrue(isSym, "Re-enabled plugin in project must be a symlink to Master Vault")
        let destination = try fm.destinationOfSymbolicLink(atPath: customPluginDir.path)
        XCTAssertEqual(destination, vaultPluginDir.path)
    }

    // MARK: - 4. Skill Deduplication
    func testSkillDeduplicationBetweenLocalAndVault() throws {
        let scanner = SkillScannerService()

        // 1. Create a Master Vault skill
        let vaultSkillDir = PathConstants.vaultSkillsDirectory.appendingPathComponent("vault-ask", isDirectory: true)
        try fm.createDirectory(at: vaultSkillDir, withIntermediateDirectories: true)
        try "---\nname: Vault Ask\ndescription: Vault ask skill\n---".write(to: vaultSkillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // 2. Create a project with:
        //    a) genuine local skill (physical directory)
        //    b) symlinked vault skill
        let projectDir = testSandboxDir.appendingPathComponent("Projects/SkillProj", isDirectory: true)
        let skillsDir = projectDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        let localSkillDir = skillsDir.appendingPathComponent("local-only-skill", isDirectory: true)
        try fm.createDirectory(at: localSkillDir, withIntermediateDirectories: true)
        try "---\nname: Local Only\ndescription: Genuine local skill\n---".write(to: localSkillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let symlinkedSkill = skillsDir.appendingPathComponent("vault-ask")
        try fm.createSymbolicLink(at: symlinkedSkill, withDestinationURL: vaultSkillDir)

        // 3. Scan project local skills
        let localSkills = scanner.scanProjectLocalSkills(projectPath: projectDir.path)

        // Assert only genuine local skill is returned, symlinked vault skill is excluded
        XCTAssertEqual(localSkills.count, 1, "scanProjectLocalSkills should return only genuine local skills")
        XCTAssertEqual(localSkills.first?.id, "local-only-skill")

        // 4. Test deduplicated count formula as used in ProjectDetailView
        let enabledSkillIds: Set<String> = ["local-only-skill", "vault-ask"]
        let localIds = Set(localSkills.map(\.id))
        let totalCount = localIds.union(enabledSkillIds).count
        XCTAssertEqual(totalCount, 2, "Total skill count should evaluate set union and never double-count")
    }

    // MARK: - 5. NewSkillSheet & createVaultSkill
    func testCreateVaultSkillGeneratesDirectoryAndSkillMd() async throws {
        let skill = try await state.createVaultSkill(
            id: "my-test-skill",
            name: "My Test Skill",
            description: "Test skill description for M4",
            category: "Swift & Apple"
        )

        XCTAssertEqual(skill.id, "my-test-skill")
        XCTAssertEqual(skill.name, "My Test Skill")
        XCTAssertEqual(skill.category, "Swift & Apple")

        let skillDir = PathConstants.vaultSkillsDirectory.appendingPathComponent("my-test-skill")
        let skillMd = skillDir.appendingPathComponent("SKILL.md")
        XCTAssertTrue(fm.fileExists(atPath: skillMd.path), "SKILL.md file must be created on disk")

        let content = try String(contentsOf: skillMd, encoding: .utf8)
        XCTAssertTrue(content.contains("name: My Test Skill"))
        XCTAssertTrue(content.contains("description: Test skill description for M4"))

        // Assert memory state is updated
        XCTAssertTrue(state.skills.contains(where: { $0.id == "my-test-skill" }))

        // Assert duplicate creation throws
        do {
            _ = try await state.createVaultSkill(
                id: "my-test-skill",
                name: "Duplicate",
                description: "Should fail"
            )
            XCTFail("Creating skill with existing ID must throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("already exists"))
        }
    }

    // MARK: - 6. EditMCPServerSheet & saveServer
    func testSaveMCPServerPersistsToVaultAndOptionallyEnablesGlobally() async throws {
        let server = MCPServerDefinition(
            id: "test-mcp-db",
            name: "Test MCP DB",
            category: "Database",
            config: [
                "command": .string("npx"),
                "args": .array([.string("-y"), .string("@supabase/mcp")]),
                "env": .object(["DB_KEY": .string("xyz123")])
            ]
        )

        await state.saveServer(server, enableGlobally: true)

        XCTAssertTrue(state.servers.contains(where: { $0.id == "test-mcp-db" }))
        XCTAssertTrue(state.globalServerIds.contains("test-mcp-db"), "Server should be enabled globally")

        // Verify persistence in Vault
        let vaultServers = await state.vaultService.loadServers()
        XCTAssertTrue(vaultServers.contains(where: { $0.id == "test-mcp-db" }))

        // Update server
        let updatedServer = MCPServerDefinition(
            id: "test-mcp-db",
            name: "Test MCP DB Updated",
            category: "Database",
            config: [
                "serverUrl": .string("https://db.example.com/sse")
            ]
        )
        await state.saveServer(updatedServer, enableGlobally: false)

        let loadedUpdated = await state.vaultService.loadServers().first(where: { $0.id == "test-mcp-db" })
        XCTAssertEqual(loadedUpdated?.name, "Test MCP DB Updated")
        XCTAssertEqual(loadedUpdated?.serverUrl, "https://db.example.com/sse")
    }

    // MARK: - 7. openTerminal Launch Target Resolution
    func testOpenTerminalTargetResolution() throws {
        let projectURL = testSandboxDir.appendingPathComponent("Projects/TestProject", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

        XCTAssertNotNil(terminalURL)
        XCTAssertTrue(fm.fileExists(atPath: terminalURL.path), "Terminal.app must exist on macOS system")

        // Calling openTerminal in XCTest resolves safely without launching external Terminal.app
        state.openTerminal(for: projectURL.path)
        XCTAssertEqual(state.statusMessage, "Terminal ready for: TestProject")
    }

    // MARK: - 8. Refresh Projects Auto-Ingests New MCP Servers from Disk
    func testRefreshProjectsIngestsNewMCPServersFromGlobalConfigAndProjects() async throws {
        _ = await state.initialLoadTask?.value

        // Initially no servers
        XCTAssertFalse(state.servers.contains(where: { $0.id == "new-cli-mcp" }))

        // 1. Simulate user adding an MCP server via global config or CLI (~/.gemini/config/mcp_config.json)
        let globalConfigDir = PathConstants.globalConfigDirectory
        try fm.createDirectory(at: globalConfigDir, withIntermediateDirectories: true)
        let globalMCPPayload: [String: Any] = [
            "mcpServers": [
                "new-cli-mcp": [
                    "command": "/opt/homebrew/bin/node",
                    "args": ["/path/to/server.js"],
                    "disabled": false
                ]
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: globalMCPPayload, options: [.prettyPrinted])
        try jsonData.write(to: PathConstants.globalMCPConfigFile)

        // 2. User clicks refresh in app
        await state.refreshProjects()

        // 3. Verify server was auto-ingested into state.servers, globalServerIds, and Master Vault
        XCTAssertTrue(state.servers.contains(where: { $0.id == "new-cli-mcp" }), "New MCP server should appear in state.servers after refresh")
        XCTAssertTrue(state.globalServerIds.contains("new-cli-mcp"), "Non-disabled global MCP should be enabled globally")

        let vaultServers = await state.vaultService.loadServers()
        XCTAssertTrue(vaultServers.contains(where: { $0.id == "new-cli-mcp" }), "New MCP server should be persisted into Master Vault")

        // 4. Test project-local MCP server ingestion
        let projectURL = testSandboxDir.appendingPathComponent("Projects/DemoProject", isDirectory: true)
        let projectPluginsDir = projectURL.appendingPathComponent(".agents/plugins/demo-plugin", isDirectory: true)
        try fm.createDirectory(at: projectPluginsDir, withIntermediateDirectories: true)
        let projectMCPPayload: [String: Any] = [
            "mcpServers": [
                "project-only-mcp": [
                    "command": "python3",
                    "args": ["server.py"]
                ]
            ]
        ]
        let projMCPData = try JSONSerialization.data(withJSONObject: projectMCPPayload)
        try projMCPData.write(to: projectPluginsDir.appendingPathComponent("mcp_config.json"))

        // Authorize folder and refresh
        ProjectFolderAccessManager.shared.saveAuthorization(url: testSandboxDir.appendingPathComponent("Projects"))
        state.isProjectsFolderAuthorized = true
        await state.refreshProjects()

        XCTAssertTrue(state.servers.contains(where: { $0.id == "project-only-mcp" }), "Project-local MCP should be auto-ingested into Master Vault upon refresh")
        let updatedVaultServers = await state.vaultService.loadServers()
        XCTAssertTrue(updatedVaultServers.contains(where: { $0.id == "project-only-mcp" }))
    }
}
