import XCTest
@testable import AntigravityManager

final class PluginMCPDeduplicationTests: XCTestCase {
    private let fm = FileManager.default
    private var sandbox: URL!
    private var projectsRoot: URL!

    override func setUp() {
        super.setUp()
        sandbox = fm.temporaryDirectory.appendingPathComponent("PluginMCPDeduplicationTests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = sandbox.appendingPathComponent(".gemini", isDirectory: true)
        projectsRoot = sandbox.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsRoot
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDown() {
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let sandbox {
            try? fm.removeItem(at: sandbox)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    private func createVaultPlugin(id: String, mcpServers: [String: [String: Any]]) throws -> PluginDefinition {
        let dir = PathConstants.vaultPluginsDirectory.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let pluginMeta = try JSONSerialization.data(withJSONObject: ["name": id], options: [.prettyPrinted])
        try pluginMeta.write(to: dir.appendingPathComponent("plugin.json"))
        let mcpPayload = try JSONSerialization.data(withJSONObject: ["mcpServers": mcpServers], options: [.prettyPrinted])
        try mcpPayload.write(to: dir.appendingPathComponent("mcp_config.json"))
        return PluginDefinition(id: id, name: PluginDefinition.formatName(id), description: "Test plugin", path: dir.path, hasMCP: true, hasSkills: false)
    }

    // MARK: - 1. SyncEngine Skips Duplicate Standalone MCPs by ID and by Normalized URL
    func testSyncProjectSkipsDuplicateStandaloneMCPByIdAndByURL() async throws {
        let projectURL = projectsRoot.appendingPathComponent("AppA", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let mobbinPlugin = try createVaultPlugin(
            id: "mobbin",
            mcpServers: ["mobbin": ["serverUrl": "https://api.mobbin.com/mcp"]]
        )
        let figmaPlugin = try createVaultPlugin(
            id: "figma",
            mcpServers: ["figma": ["serverUrl": "https://mcp.figma.com/mcp"]]
        )

        let standaloneMobbin = MCPServerDefinition(
            id: "mobbin",
            config: ["serverUrl": .string("https://api.mobbin.com/mcp")]
        )
        let urlAliasMobbin = MCPServerDefinition(
            id: "mobbin-custom-alias",
            config: ["serverUrl": .string("https://api.mobbin.com/mcp/")]
        )
        let legacyFigma = MCPServerDefinition(
            id: "figma",
            config: ["command": .string("figma-developer-mcp")]
        )
        let independentServer = MCPServerDefinition(
            id: "supabase",
            config: ["serverUrl": .string("https://mcp.supabase.com/mcp")]
        )

        let project = ProjectProfile(
            id: "app-a",
            name: "AppA",
            path: projectURL.path,
            enabledMCPServerIds: ["mobbin", "mobbin-custom-alias", "figma", "supabase"],
            enabledPluginIds: ["mobbin", "figma"]
        )

        let engine = SyncEngine()
        try await engine.syncProject(
            project: project,
            allServers: [standaloneMobbin, urlAliasMobbin, legacyFigma, independentServer],
            allSkills: [],
            allPlugins: [mobbinPlugin, figmaPlugin]
        )

        // agy-manager must ONLY contain supabase
        let agyMCPFile = projectURL.appendingPathComponent(".agents/plugins/agy-manager/mcp_config.json")
        let agyData = try Data(contentsOf: agyMCPFile)
        let agyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: agyData) as? [String: Any])
        let agyServers = try XCTUnwrap(agyJSON["mcpServers"] as? [String: Any])
        XCTAssertEqual(Set(agyServers.keys), ["supabase"])

        // Claude project config must use plugin's official figma URL (not legacy stdio) and keep mobbin + supabase
        let claudeData = try Data(contentsOf: PathConstants.claudeConfigFile)
        let claudeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: claudeData) as? [String: Any])
        let claudeProjects = try XCTUnwrap(claudeJSON["projects"] as? [String: [String: Any]])
        let claudeServers = try XCTUnwrap(claudeProjects[projectURL.path]?["mcpServers"] as? [String: [String: Any]])
        XCTAssertEqual(Set(claudeServers.keys), ["figma", "mobbin", "supabase"])
        XCTAssertEqual(claudeServers["figma"]?["url"] as? String, "https://mcp.figma.com/mcp")
        XCTAssertNil(claudeServers["figma"]?["command"])

        // When only duplicate standalone MCPs remain, agy-manager directory must be deleted completely
        var onlyDuplicates = project
        onlyDuplicates.enabledMCPServerIds = ["mobbin", "figma"]
        try await engine.syncProject(
            project: onlyDuplicates,
            allServers: [standaloneMobbin, legacyFigma],
            allSkills: [],
            allPlugins: [mobbinPlugin, figmaPlugin]
        )
        let agyDir = projectURL.appendingPathComponent(".agents/plugins/agy-manager")
        XCTAssertFalse(fm.fileExists(atPath: agyDir.path), "agy-manager must be removed when all enabled standalone MCPs are covered by active plugins")
    }

    // MARK: - 2. CLI `set` Prevents Enabling Duplicate MCP and Auto-Replaces When Enabling Plugin
    func testCLISetPreventsAndAutoReplacesDuplicateMCPs() async throws {
        let projectURL = projectsRoot.appendingPathComponent("CLIDedup", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()

        _ = try createVaultPlugin(
            id: "mobbin",
            mcpServers: ["mobbin": ["serverUrl": "https://api.mobbin.com/mcp"]]
        )
        await vault.saveServers([
            MCPServerDefinition(id: "mobbin", config: ["serverUrl": .string("https://api.mobbin.com/mcp")]),
            MCPServerDefinition(id: "xcode", config: ["command": .string("/usr/bin/xcrun"), "args": .array([.string("mcpbridge")])])
        ])
        await vault.saveProjects([
            ProjectProfile(
                id: "cli-dedup",
                name: "CLIDedup",
                path: projectURL.path,
                enabledMCPServerIds: ["mobbin", "xcode"],
                enabledPluginIds: []
            )
        ])

        // 1. Enabling mobbin plugin must auto-disable standalone mobbin MCP
        let res1 = await CLIRunner.execute(
            arguments: ["agymg", "set", "--project", projectURL.path, "--enable-plugin", "mobbin", "--json"]
        )
        XCTAssertEqual(res1.exitCode, 0, res1.stderr)
        let decoded1 = try JSONDecoder().decode(CLISetResponse.self, from: Data(res1.stdout.utf8))
        XCTAssertEqual(decoded1.enabledPlugins, ["mobbin"])
        XCTAssertTrue(decoded1.disabledMCPs.contains("mobbin"))
        XCTAssertEqual(decoded1.skippedDuplicateMCPs, ["mobbin (via plugin 'mobbin')"])

        let projectsAfter1 = await vault.loadSavedProjectsWithoutTCC(allowingCWD: projectURL.path)
        let proj1 = try XCTUnwrap(projectsAfter1.first(where: { $0.id == "cli-dedup" }))
        XCTAssertEqual(proj1.enabledMCPServerIds, ["xcode"])
        XCTAssertEqual(proj1.enabledPluginIds, ["mobbin"])

        // 2. Attempting to re-enable standalone mobbin MCP while mobbin plugin is active must be skipped
        let res2 = await CLIRunner.execute(
            arguments: ["agymg", "set", "--project", projectURL.path, "--enable-mcp", "mobbin", "--json"]
        )
        XCTAssertEqual(res2.exitCode, 0, res2.stderr)
        let decoded2 = try JSONDecoder().decode(CLISetResponse.self, from: Data(res2.stdout.utf8))
        XCTAssertTrue(decoded2.enabledMCPs.isEmpty)
        XCTAssertEqual(decoded2.skippedDuplicateMCPs, ["mobbin (via plugin 'mobbin')"])
        XCTAssertTrue(decoded2.message.contains("Skipped/replaced duplicate"))

        let projectsAfter2 = await vault.loadSavedProjectsWithoutTCC(allowingCWD: projectURL.path)
        let proj2 = try XCTUnwrap(projectsAfter2.first(where: { $0.id == "cli-dedup" }))
        XCTAssertEqual(proj2.enabledMCPServerIds, ["xcode"])
    }

    // MARK: - 3. Scanner and VaultService Do Not Re-Ingest Plugin-Bundled MCPs Into Standalone State
    func testScannerAndVaultDoNotReIngestPluginBundledMCPs() async throws {
        let projectURL = projectsRoot.appendingPathComponent("ScanClean", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let mobbinPlugin = try createVaultPlugin(
            id: "mobbin",
            mcpServers: ["mobbin": ["serverUrl": "https://api.mobbin.com/mcp"]]
        )
        let xcodeServer = MCPServerDefinition(
            id: "xcode",
            config: ["command": .string("/usr/bin/xcrun"), "args": .array([.string("mcpbridge")])]
        )
        let project = ProjectProfile(
            id: "scan-clean",
            name: "ScanClean",
            path: projectURL.path,
            enabledMCPServerIds: ["xcode"],
            enabledPluginIds: ["mobbin"]
        )

        // Sync project -> writes .agents/plugins/mobbin/mcp_config.json AND ~/.claude.json projects[path].mcpServers.mobbin
        try await SyncEngine().syncProject(
            project: project,
            allServers: [xcodeServer],
            allSkills: [],
            allPlugins: [mobbinPlugin]
        )

        // ProjectScannerService must NOT copy plugin-bundled 'mobbin' into enabledMCPServerIds
        let discovered = ProjectScannerService().discoverProjects(in: projectsRoot, scanDefaultWhenNil: false)
        let canonicalProjectPath = projectURL.resolvingSymlinksInPath().path
        let scannedProj = try XCTUnwrap(discovered.first(where: {
            URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == canonicalProjectPath
        }))
        XCTAssertEqual(scannedProj.enabledPluginIds, ["mobbin"])
        XCTAssertEqual(scannedProj.enabledMCPServerIds, ["xcode"])

        // VaultService.scanAndIngestServers must NOT ingest plugin-bundled 'mobbin' into master_mcp.json
        // Even for a physical (non-managed) repo-local plugin like silueta-mcp
        let localPluginDir = projectURL.appendingPathComponent(".agents/plugins/custom-bundle", isDirectory: true)
        try fm.createDirectory(at: localPluginDir, withIntermediateDirectories: true)
        let localMCP = try JSONSerialization.data(
            withJSONObject: ["mcpServers": ["bundled-only": ["serverUrl": "https://bundled.example.com/mcp"]]]
        )
        try localMCP.write(to: localPluginDir.appendingPathComponent("mcp_config.json"))

        let vault = VaultService()
        await vault.saveServers([xcodeServer])
        let (ingested, _) = await vault.scanAndIngestServers(projects: [scannedProj])
        let ingestedIds = Set(ingested.map(\.id))
        XCTAssertTrue(ingestedIds.contains("xcode"))
        XCTAssertFalse(ingestedIds.contains("mobbin"))
        XCTAssertFalse(ingestedIds.contains("bundled-only"))
    }

    // MARK: - 4. AppState Toggles & Doctor Detect/Prevent Duplicate MCPs
    @MainActor
    func testAppStateTogglesAndDoctorGuardDuplicateMCPs() async throws {
        let projectURL = projectsRoot.appendingPathComponent("GUIGuard", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let mobbinPlugin = try createVaultPlugin(
            id: "mobbin",
            mcpServers: ["mobbin": ["serverUrl": "https://api.mobbin.com/mcp"]]
        )
        let mobbinServer = MCPServerDefinition(
            id: "mobbin",
            config: ["serverUrl": .string("https://api.mobbin.com/mcp")]
        )

        let state = AppState(autoload: false)
        state.servers = [mobbinServer]
        state.plugins = [mobbinPlugin]
        state.projects = [
            ProjectProfile(
                id: "gui-guard",
                name: "GUIGuard",
                path: projectURL.path,
                enabledMCPServerIds: ["mobbin"],
                enabledPluginIds: []
            )
        ]

        // Enabling plugin auto-removes conflicting standalone MCP
        state.toggleProjectPlugin(projectId: "gui-guard", pluginId: "mobbin")
        XCTAssertEqual(state.projects[0].enabledPluginIds, ["mobbin"])
        XCTAssertTrue(state.projects[0].enabledMCPServerIds.isEmpty)

        // Attempting to enable conflicting standalone MCP is blocked with feedback
        state.toggleProjectServer(projectId: "gui-guard", serverId: "mobbin")
        XCTAssertTrue(state.projects[0].enabledMCPServerIds.isEmpty)
        XCTAssertTrue(state.popoverFeedback?.message.contains("Already provided by") ?? false)

        // Doctor detects manually injected overlap in projects.json
        var dirtyProject = state.projects[0]
        dirtyProject.enabledMCPServerIds = ["mobbin"]
        let drift = MCPDiagnosticsService().detectDrift(
            servers: [mobbinServer],
            globalServerIds: [],
            skills: [],
            globalSkillIds: [],
            projects: [dirtyProject],
            plugins: [mobbinPlugin],
            globalPluginIds: []
        )
        XCTAssertTrue(
            drift.issues.contains(where: { $0.id == "drift:duplicate-mcp:proj:gui-guard:mobbin" }),
            "detectDrift must report duplicate MCP warning when standalone MCP overlaps enabled plugin"
        )
        state.cancelPendingTasks()
    }
}
