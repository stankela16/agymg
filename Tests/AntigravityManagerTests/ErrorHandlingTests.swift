import XCTest
@testable import AntigravityManager

final class ErrorHandlingTests: XCTestCase {
    private var testSandboxDir: URL!
    private var tempDir: URL {
        testSandboxDir
    }

    override func setUp() {
        super.setUp()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ErrorHandlingTests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        testSandboxDir = dir
        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDown() {
        let fm = FileManager.default
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let dir = testSandboxDir {
            try? fm.removeItem(at: dir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    // MARK: - 1. Register Project Folder Missing Path Graceful Failure
    @MainActor
    func testRegisterProjectFolderMissingPathGracefulFailure() async {
        let state = AppState()
        let fm = FileManager.default
        let missingURL = tempDir.appendingPathComponent("nonexistent_folder_abc123")
        XCTAssertFalse(fm.fileExists(atPath: missingURL.path))

        await state.registerProjectFolder(at: missingURL)

        XCTAssertEqual(
            state.statusMessage,
            "Project folder does not exist at the specified path",
            "Must report graceful error message in statusMessage without throwing fatalError"
        )
        XCTAssertFalse(
            state.projects.contains(where: { $0.id == "nonexistent_folder_abc123" }),
            "Non-existent folder must not be registered into state.projects"
        )
        state.cancelPendingTasks()
    }

    // MARK: - 2. Project Scanner Non-existent Directory Returns Empty
    func testProjectScannerNonexistentDirectoryReturnsEmpty() {
        let scanner = ProjectScannerService()
        let fm = FileManager.default
        let nonexistentDir = tempDir.appendingPathComponent("missing_projects_dir", isDirectory: true)
        XCTAssertFalse(fm.fileExists(atPath: nonexistentDir.path))

        let results = scanner.discoverProjects(in: nonexistentDir)
        XCTAssertTrue(results.isEmpty, "discoverProjects in non-existent directory must return empty array without throwing")
    }

    // MARK: - 3. Plugin Scanner Non-existent Projects Handling
    func testPluginScannerNonexistentProjectsHandling() {
        let pScanner = PluginScannerService()
        let missingPath = tempDir.appendingPathComponent("missing_plugins_dir", isDirectory: true)

        // 1. scanPlugins with missing directory
        let missingPlugins = pScanner.scanPlugins(in: missingPath)
        XCTAssertTrue(missingPlugins.isEmpty, "scanPlugins must return empty array for non-existent directory")

        // 2. scanProjectPlugins with missing project path
        let projectPlugins = pScanner.scanProjectPlugins(projectPath: "/tmp/nonexistent_project_xyz_\(UUID().uuidString)")
        XCTAssertTrue(projectPlugins.isEmpty, "scanProjectPlugins must return empty array for non-existent project")

        // 3. scanAllPlugins with ghost projects
        let ghostProject = ProjectProfile(
            id: "ghost",
            name: "Ghost Project",
            path: "/tmp/ghost_path_\(UUID().uuidString)"
        )
        let allPlugins = pScanner.scanAllPlugins(projects: [ghostProject])
        XCTAssertNotNil(allPlugins)
        XCTAssertFalse(allPlugins.contains(where: { $0.id == "ghost" }))
    }

    // MARK: - 4. Skill Scanner Non-existent Directory Handling
    func testSkillScannerNonexistentDirectoryHandling() {
        let sScanner = SkillScannerService()

        // 1. scanProjectLocalSkills with non-existent project directory
        let missingLocalSkills = sScanner.scanProjectLocalSkills(
            projectPath: "/tmp/nonexistent_skills_proj_\(UUID().uuidString)"
        )
        XCTAssertTrue(missingLocalSkills.isEmpty, "scanProjectLocalSkills must return empty array for missing path")

        // 2. scanBuiltinSkills when directory does not exist
        let builtins = sScanner.scanBuiltinSkills()
        XCTAssertTrue(builtins.isEmpty, "scanBuiltinSkills in hermetic sandbox with no builtin dir must return empty array")

        // 3. scanVaultSkills in empty sandbox
        let vaultSkills = sScanner.scanVaultSkills()
        XCTAssertTrue(vaultSkills.isEmpty, "scanVaultSkills in empty sandbox with no skills must return empty array")
    }

    // MARK: - 5. Corrupted MCP Config JSON Handling
    func testCorruptedMcpConfigJsonHandling() async throws {
        let fm = FileManager.default

        // 1. Corrupt vault master_mcp.json
        let vaultFile = PathConstants.vaultMCPFile
        try fm.createDirectory(at: vaultFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let malformedJson = "{ this is completely invalid JSON content <<>> !@#$ }"
        try malformedJson.write(to: vaultFile, atomically: true, encoding: .utf8)

        let vault = VaultService()
        let servers = await vault.loadServers()
        XCTAssertTrue(servers.isEmpty, "VaultService.loadServers must catch decode error and return empty array without crashing")

        // 2. Corrupt global mcp_config.json
        let globalFile = PathConstants.globalMCPConfigFile
        try fm.createDirectory(at: globalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try malformedJson.write(to: globalFile, atomically: true, encoding: .utf8)

        let syncEngine = SyncEngine()
        // Sync global config should safely overwrite corrupted file
        let newServer = MCPServerDefinition(
            id: "recovery-server",
            name: "Recovery",
            category: "tools",
            config: ["command": .string("node")]
        )
        try await syncEngine.syncGlobalConfig(servers: [newServer], enabledIds: ["recovery-server"])

        let recoveredData = try Data(contentsOf: globalFile)
        let recoveredJson = try JSONSerialization.jsonObject(with: recoveredData) as? [String: Any]
        let mcpServers = recoveredJson?["mcpServers"] as? [String: [String: Any]]
        XCTAssertNotNil(mcpServers?["recovery-server"], "syncGlobalConfig must successfully overwrite corrupted file with valid JSON")

        // 3. Corrupt project plugin mcp_config.json
        let projectDir = tempDir.appendingPathComponent("CorruptedPluginProject", isDirectory: true)
        let pluginMcpDir = projectDir.appendingPathComponent(".agents/plugins/corrupted-plugin", isDirectory: true)
        try fm.createDirectory(at: pluginMcpDir, withIntermediateDirectories: true)
        let pluginMcpFile = pluginMcpDir.appendingPathComponent("mcp_config.json")
        try malformedJson.write(to: pluginMcpFile, atomically: true, encoding: .utf8)

        let scanner = ProjectScannerService()
        let discovered = scanner.discoverProjects(in: tempDir)
        let discoveredProj = discovered.first(where: { $0.name == "CorruptedPluginProject" })
        XCTAssertNotNil(discoveredProj)
        XCTAssertFalse(
            discoveredProj?.enabledMCPServerIds.contains("corrupted-plugin") == true,
            "Corrupted plugin MCP file must not throw or add invalid server IDs"
        )
    }
}
