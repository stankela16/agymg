import XCTest
@testable import AntigravityManager

final class SyncEngineTests: XCTestCase {
    private var testSandboxDir: URL!
    private var tempDir: URL {
        testSandboxDir
    }
    private let fm = FileManager.default
    private var syncEngine: SyncEngine!

    override func setUp() {
        super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("SyncEngineTests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        testSandboxDir = dir
        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        syncEngine = SyncEngine()
    }

    override func tearDown() {
        syncEngine = nil
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let dir = testSandboxDir {
            try? fm.removeItem(at: dir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    // MARK: - 1. Sync Project Generates AgyManager Plugin and McpConfig
    func testSyncProjectGeneratesAgyManagerPluginAndMcpConfig() async throws {
        let projectURL = tempDir.appendingPathComponent("TestProject", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let server = MCPServerDefinition(
            id: "alpha-server",
            name: "Alpha Server",
            category: "core",
            config: [
                "command": .string("node"),
                "args": .array([.string("alpha.js")]),
                "disabled": .bool(true) // Should be stripped out by syncProject
            ]
        )

        let project = ProjectProfile(
            id: "proj-1",
            name: "TestProject",
            path: projectURL.path,
            enabledMCPServerIds: ["alpha-server"],
            enabledSkillIds: [],
            enabledPluginIds: []
        )

        try await syncEngine.syncProject(
            project: project,
            allServers: [server],
            allSkills: [],
            allPlugins: []
        )

        // Verify .agents/plugins/agy-manager/plugin.json
        let pluginDir = projectURL.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        let pluginJsonURL = pluginDir.appendingPathComponent("plugin.json")
        XCTAssertTrue(fm.fileExists(atPath: pluginJsonURL.path), "plugin.json must exist")

        let metaData = try Data(contentsOf: pluginJsonURL)
        let metaJson = try JSONSerialization.jsonObject(with: metaData) as? [String: Any]
        XCTAssertEqual(metaJson?["name"] as? String, "agy-manager")

        // Verify .agents/plugins/agy-manager/mcp_config.json
        let mcpConfigURL = pluginDir.appendingPathComponent("mcp_config.json")
        XCTAssertTrue(fm.fileExists(atPath: mcpConfigURL.path), "mcp_config.json must exist")

        let mcpData = try Data(contentsOf: mcpConfigURL)
        let mcpJson = try JSONSerialization.jsonObject(with: mcpData) as? [String: Any]
        guard let servers = mcpJson?["mcpServers"] as? [String: [String: Any]],
              let alphaConfig = servers["alpha-server"] else {
            XCTFail("mcpServers must contain alpha-server")
            return
        }

        XCTAssertEqual(alphaConfig["command"] as? String, "node")
        XCTAssertEqual(alphaConfig["args"] as? [String], ["alpha.js"])
        XCTAssertNil(alphaConfig["disabled"], "\"disabled\" key must be omitted in project-level MCP config")
    }

    // MARK: - 2. Sync Project Prunes AgyManager When No Servers
    func testSyncProjectPrunesAgyManagerWhenNoServers() async throws {
        let projectURL = tempDir.appendingPathComponent("EmptyServerProject", isDirectory: true)
        let pluginDir = projectURL.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let dummyFile = pluginDir.appendingPathComponent("mcp_config.json")
        try "{}".write(to: dummyFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(fm.fileExists(atPath: pluginDir.path))

        let project = ProjectProfile(
            id: "empty-proj",
            name: "EmptyServerProject",
            path: projectURL.path,
            enabledMCPServerIds: [] // No servers enabled
        )

        try await syncEngine.syncProject(
            project: project,
            allServers: [],
            allSkills: [],
            allPlugins: []
        )

        XCTAssertFalse(
            fm.fileExists(atPath: pluginDir.path),
            ".agents/plugins/agy-manager must be deleted when no MCP servers are enabled for the project"
        )
    }

    // MARK: - 3. Sync Project Symlink Skill Creation and Pruning
    func testSyncProjectSymlinkSkillCreationAndPruning() async throws {
        let vaultSkillsDir = PathConstants.vaultSkillsDirectory
        let vaultSkillURL = vaultSkillsDir.appendingPathComponent("test-skill", isDirectory: true)
        try fm.createDirectory(at: vaultSkillURL, withIntermediateDirectories: true)
        let skillMdURL = vaultSkillURL.appendingPathComponent("SKILL.md")
        try "# Test Skill\nDescription: Vault Skill".write(to: skillMdURL, atomically: true, encoding: .utf8)

        let projectURL = tempDir.appendingPathComponent("SkillProject", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let skillDef = SkillDefinition(
            id: "test-skill",
            name: "Test Skill",
            description: "Vault Skill",
            category: "tools",
            path: vaultSkillURL.path,
            origin: .vault
        )

        var project = ProjectProfile(
            id: "skill-proj",
            name: "SkillProject",
            path: projectURL.path,
            enabledMCPServerIds: [],
            enabledSkillIds: ["test-skill"],
            enabledPluginIds: []
        )

        // 1. Sync with skill enabled -> Symlink must be created
        try await syncEngine.syncProject(
            project: project,
            allServers: [],
            allSkills: [skillDef],
            allPlugins: []
        )

        let projectSkillURL = projectURL.appendingPathComponent(".agents/skills/test-skill", isDirectory: true)
        let isLink = await syncEngine.isSymlink(at: projectSkillURL)
        XCTAssertTrue(isLink, "Project skill must be created as a symbolic link")

        let symlinkDest = try fm.destinationOfSymbolicLink(atPath: projectSkillURL.path)
        XCTAssertEqual(symlinkDest, vaultSkillURL.path, "Symlink destination must match vault skill path")

        // 2. Disable skill -> Symlink must be pruned without deleting vault source
        project.enabledSkillIds = []
        try await syncEngine.syncProject(
            project: project,
            allServers: [],
            allSkills: [skillDef],
            allPlugins: []
        )

        XCTAssertFalse(
            fm.fileExists(atPath: projectSkillURL.path),
            "Project skill symlink must be removed when disabled"
        )
        XCTAssertTrue(
            fm.fileExists(atPath: vaultSkillURL.path),
            "Original vault skill must NOT be removed when pruned from project"
        )
        XCTAssertTrue(
            fm.fileExists(atPath: skillMdURL.path),
            "Original SKILL.md in vault must remain intact"
        )
    }

    // MARK: - 4. Sync Project Ensure Gitignore Protection
    func testSyncProjectEnsureGitignoreProtection() async throws {
        let projectURL = tempDir.appendingPathComponent("GitignoreProject", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let gitignoreURL = projectURL.appendingPathComponent(".gitignore")

        // Case A: Missing .gitignore -> Creates with protection block
        await syncEngine.ensureGitignore(at: projectURL)
        XCTAssertTrue(fm.fileExists(atPath: gitignoreURL.path))
        var content = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertTrue(content.contains(".agents/plugins/agy-manager/"))
        XCTAssertTrue(content.contains(".agents/mcp_config.json"))

        // Case B: Existing file without .agents -> Appends protection block
        try fm.removeItem(at: gitignoreURL)
        let initialUserGitignore = "node_modules/\n.DS_Store\n"
        try initialUserGitignore.write(to: gitignoreURL, atomically: true, encoding: .utf8)

        await syncEngine.ensureGitignore(at: projectURL)
        content = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertTrue(content.contains("node_modules/"))
        XCTAssertTrue(content.contains(".DS_Store"))
        XCTAssertTrue(content.contains(".agents/plugins/agy-manager/"))

        // Case C: Idempotency -> Subsequent calls do not duplicate lines
        await syncEngine.ensureGitignore(at: projectURL)
        content = try String(contentsOf: gitignoreURL, encoding: .utf8)
        let occurrences = content.components(separatedBy: ".agents/plugins/agy-manager/").count - 1
        XCTAssertEqual(occurrences, 1, ".gitignore must not contain duplicated protection blocks")

        // Case D: Existing file already containing .agents/ -> Left untouched
        try fm.removeItem(at: gitignoreURL)
        let alreadyCovered = ".agents/\nbuild/\n"
        try alreadyCovered.write(to: gitignoreURL, atomically: true, encoding: .utf8)

        await syncEngine.ensureGitignore(at: projectURL)
        content = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertEqual(content, alreadyCovered, "If .agents/ is already ignored, file should not be modified")
    }

    // MARK: - 5. Sync Global Config Generates Valid JSON and Backup
    func testSyncGlobalConfigGeneratesValidJsonAndBackup() async throws {
        let globalConfigDir = PathConstants.globalConfigDirectory
        try fm.createDirectory(at: globalConfigDir, withIntermediateDirectories: true)

        let server1 = MCPServerDefinition(
            id: "server-active",
            name: "Server Active",
            category: "core",
            config: ["command": .string("npx")]
        )
        let server2 = MCPServerDefinition(
            id: "server-inactive",
            name: "Server Inactive",
            category: "tools",
            config: ["command": .string("python")]
        )

        // 1. Initial sync
        try await syncEngine.syncGlobalConfig(
            servers: [server1, server2],
            enabledIds: ["server-active"]
        )

        let globalFile = PathConstants.globalMCPConfigFile
        XCTAssertTrue(fm.fileExists(atPath: globalFile.path))

        let data = try Data(contentsOf: globalFile)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let servers = json?["mcpServers"] as? [String: [String: Any]] else {
            XCTFail("mcpServers dictionary missing")
            return
        }

        XCTAssertEqual(servers["server-active"]?["disabled"] as? Bool, false)
        XCTAssertEqual(servers["server-inactive"]?["disabled"] as? Bool, true)

        // 2. Second sync -> Backup file must be created from previous version
        let backupFile = globalConfigDir.appendingPathComponent("mcp_config.json.bak")
        try await syncEngine.syncGlobalConfig(
            servers: [server1, server2],
            enabledIds: ["server-active", "server-inactive"]
        )

        XCTAssertTrue(fm.fileExists(atPath: backupFile.path), "Backup mcp_config.json.bak must be preserved/created")
        let updatedData = try Data(contentsOf: globalFile)
        let updatedJson = try JSONSerialization.jsonObject(with: updatedData) as? [String: Any]
        let updatedServers = updatedJson?["mcpServers"] as? [String: [String: Any]]
        XCTAssertEqual(updatedServers?["server-inactive"]?["disabled"] as? Bool, false)
    }

    // MARK: - 6. Is Symlink Method
    func testIsSymlinkMethod() async throws {
        let regularFile = tempDir.appendingPathComponent("regular_file.txt")
        try "hello".write(to: regularFile, atomically: true, encoding: .utf8)

        let symlinkFile = tempDir.appendingPathComponent("symlink_file.txt")
        try fm.createSymbolicLink(at: symlinkFile, withDestinationURL: regularFile)

        let regularDir = tempDir.appendingPathComponent("regular_folder", isDirectory: true)
        try fm.createDirectory(at: regularDir, withIntermediateDirectories: true)

        let symlinkDir = tempDir.appendingPathComponent("symlink_folder", isDirectory: true)
        try fm.createSymbolicLink(at: symlinkDir, withDestinationURL: regularDir)

        let nonexistent = tempDir.appendingPathComponent("nonexistent.txt")

        // Assertions
        let isLinkFile = await syncEngine.isSymlink(at: symlinkFile)
        XCTAssertTrue(isLinkFile, "isSymlink must return true for symlink to file")

        let isRegularFile = await syncEngine.isSymlink(at: regularFile)
        XCTAssertFalse(isRegularFile, "isSymlink must return false for regular file")

        let isLinkDir = await syncEngine.isSymlink(at: symlinkDir)
        XCTAssertTrue(isLinkDir, "isSymlink must return true for symlink to directory")

        let isRegularDir = await syncEngine.isSymlink(at: regularDir)
        XCTAssertFalse(isRegularDir, "isSymlink must return false for regular directory")

        let isNonexistent = await syncEngine.isSymlink(at: nonexistent)
        XCTAssertFalse(isNonexistent, "isSymlink must return false for non-existent path")
    }

    // MARK: - 7. Purge Server Completely Cleans Global and Projects
    func testPurgeServerCompletelyCleansGlobalAndProjects() async throws {
        let globalConfigDir = PathConstants.globalConfigDirectory
        try fm.createDirectory(at: globalConfigDir, withIntermediateDirectories: true)

        // Write global mcp_config.json
        let globalFile = PathConstants.globalMCPConfigFile
        let globalPayload: [String: Any] = [
            "mcpServers": [
                "server-to-purge": ["command": "node", "disabled": false],
                "server-to-keep": ["command": "python", "disabled": false]
            ]
        ]
        let globalData = try JSONSerialization.data(withJSONObject: globalPayload, options: [.prettyPrinted])
        try globalData.write(to: globalFile)

        // Setup Project 1 with both servers
        let p1URL = tempDir.appendingPathComponent("Project1", isDirectory: true)
        let p1PluginDir = p1URL.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: p1PluginDir, withIntermediateDirectories: true)
        let p1McpFile = p1PluginDir.appendingPathComponent("mcp_config.json")
        let p1Payload: [String: Any] = [
            "mcpServers": [
                "server-to-purge": ["command": "node"],
                "server-to-keep": ["command": "python"]
            ]
        ]
        let p1Data = try JSONSerialization.data(withJSONObject: p1Payload, options: [.prettyPrinted])
        try p1Data.write(to: p1McpFile)

        // Setup Project 2 with only server-to-purge
        let p2URL = tempDir.appendingPathComponent("Project2", isDirectory: true)
        let p2PluginDir = p2URL.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: p2PluginDir, withIntermediateDirectories: true)
        let p2McpFile = p2PluginDir.appendingPathComponent("mcp_config.json")
        let p2Payload: [String: Any] = [
            "mcpServers": [
                "server-to-purge": ["command": "node"]
            ]
        ]
        let p2Data = try JSONSerialization.data(withJSONObject: p2Payload, options: [.prettyPrinted])
        try p2Data.write(to: p2McpFile)

        let p1 = ProjectProfile(id: "p1", name: "Project1", path: p1URL.path, enabledMCPServerIds: ["server-to-purge", "server-to-keep"])
        let p2 = ProjectProfile(id: "p2", name: "Project2", path: p2URL.path, enabledMCPServerIds: ["server-to-purge"])

        // Perform Purge
        try await syncEngine.purgeServerCompletely(id: "server-to-purge", allProjects: [p1, p2])

        // 1. Verify global config: server-to-purge removed, server-to-keep preserved
        let updatedGlobalData = try Data(contentsOf: globalFile)
        let updatedGlobalJson = try JSONSerialization.jsonObject(with: updatedGlobalData) as? [String: Any]
        let updatedGlobalServers = updatedGlobalJson?["mcpServers"] as? [String: Any]
        XCTAssertNil(updatedGlobalServers?["server-to-purge"], "server-to-purge must be removed from global config")
        XCTAssertNotNil(updatedGlobalServers?["server-to-keep"], "server-to-keep must remain in global config")

        // 2. Verify Project 1: server-to-purge removed, server-to-keep preserved
        let updatedP1Data = try Data(contentsOf: p1McpFile)
        let updatedP1Json = try JSONSerialization.jsonObject(with: updatedP1Data) as? [String: Any]
        let updatedP1Servers = updatedP1Json?["mcpServers"] as? [String: Any]
        XCTAssertNil(updatedP1Servers?["server-to-purge"], "server-to-purge must be removed from Project 1")
        XCTAssertNotNil(updatedP1Servers?["server-to-keep"], "server-to-keep must remain in Project 1")

        // 3. Verify Project 2: agy-manager folder deleted because servers became empty
        XCTAssertFalse(
            fm.fileExists(atPath: p2PluginDir.path),
            "Project 2 agy-manager folder must be deleted when its only server was purged"
        )
    }

    // MARK: - 8. Sync Claude Global Skills Propagates Shared .claude Symlinks (Projects & Plans) to Profiles
    func testSyncClaudeGlobalSkillsPropagatesSharedClaudeSymlinksToProfiles() async throws {
        let primaryClaudeDir = PathConstants.claudeDirectory
        try fm.createDirectory(at: primaryClaudeDir.appendingPathComponent("hooks", isDirectory: true), withIntermediateDirectories: true)
        try "# Global Rules".write(to: primaryClaudeDir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: primaryClaudeDir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let p2Home = PathConstants.effectiveHomeDirectory
            .appendingPathComponent("AntigravityProfiles/Profile2/home", isDirectory: true)
        let p2Claude = p2Home.appendingPathComponent(".claude", isDirectory: true)
        let p2Sessions = p2Claude.appendingPathComponent("sessions", isDirectory: true)
        try fm.createDirectory(at: p2Sessions, withIntermediateDirectories: true)

        await syncEngine.syncClaudeGlobalSkills(allSkills: [], enabledSkillIds: [])

        for sharedItem in ["skills", "CLAUDE.md", "hooks", "settings.json", "projects", "plans"] {
            let dst = p2Claude.appendingPathComponent(sharedItem)
            let expectedSrc = primaryClaudeDir.appendingPathComponent(sharedItem).path
            let linkDest = try? fm.destinationOfSymbolicLink(atPath: dst.path)
            XCTAssertEqual(linkDest, expectedSrc, "Profile .claude/\(sharedItem) must be symlinked to primary .claude/\(sharedItem)")
        }

        let isSessionsSymlink = await syncEngine.isSymlink(at: p2Sessions)
        XCTAssertFalse(isSessionsSymlink, "Profile .claude/sessions must remain a local directory")
        XCTAssertTrue(fm.fileExists(atPath: p2Sessions.path), "Profile .claude/sessions must be preserved")
    }

    // MARK: - 9. Sync Claude Global Config Uses Dynamic HeadersHelper and Bypasses Connectors
    func testSyncClaudeGlobalConfigUsesDynamicHeadersHelperAndBypassesConnectors() async throws {
        let mobbinServer = MCPServerDefinition(
            id: "mobbin",
            name: "mobbin",
            category: "Tools",
            config: ["serverUrl": .string("https://api.mobbin.com/mcp")]
        )
        let stitchServer = MCPServerDefinition(
            id: "stitch",
            name: "stitch",
            category: "Tools",
            config: [
                "serverUrl": .string("https://stitch.googleapis.com/mcp"),
                "headers": .object(["X-Goog-Api-Key": .string("secret-key")])
            ]
        )

        let oauthTokensURL = PathConstants.engineMCPOAuthTokensFile
        try fm.createDirectory(at: oauthTokensURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oauthPayload: [String: Any] = [
            "https://api.mobbin.com/mcp": [
                "server_url": "https://api.mobbin.com/mcp",
                "token": [
                    "access_token": "tok_mobbin_123",
                    "refresh_token": "ref_mobbin_123"
                ]
            ]
        ]
        let oauthData = try JSONSerialization.data(withJSONObject: oauthPayload)
        try oauthData.write(to: oauthTokensURL)

        let authCache = PathConstants.claudeDirectory.appendingPathComponent("mcp-needs-auth-cache.json")
        try fm.createDirectory(at: PathConstants.claudeDirectory, withIntermediateDirectories: true)
        try "{\"mobbin\":{\"timestamp\":123},\"unrelated-oauth\":{\"timestamp\":456}}"
            .write(to: authCache, atomically: true, encoding: .utf8)
        try "{\"disableClaudeAiConnectors\":false,\"enabledPlugins\":{\"browser-use@synced\":true}}"
            .write(to: PathConstants.claudeSettingsFile, atomically: true, encoding: .utf8)

        try await syncEngine.syncGlobalConfig(
            servers: [mobbinServer, stitchServer],
            enabledIds: ["mobbin", "stitch"]
        )

        let claudeConfigData = try Data(contentsOf: PathConstants.claudeConfigFile)
        let claudeJson = try JSONSerialization.jsonObject(with: claudeConfigData) as? [String: Any]
        let mcpServers = claudeJson?["mcpServers"] as? [String: [String: Any]]

        let mobbinConfig = mcpServers?["mobbin"]
        XCTAssertEqual(mobbinConfig?["type"] as? String, "http")
        XCTAssertEqual(mobbinConfig?["url"] as? String, "https://api.mobbin.com/mcp")
        XCTAssertEqual(mobbinConfig?["headersHelper"] as? String, PathConstants.claudeMCPOAuthHelperScript.path)
        XCTAssertNil(mobbinConfig?["headers"], "OAuth HTTP servers must use dynamic headersHelper instead of static expiring headers")

        let stitchConfig = mcpServers?["stitch"]
        XCTAssertEqual(stitchConfig?["type"] as? String, "http")
        XCTAssertEqual((stitchConfig?["headers"] as? [String: String])?["X-Goog-Api-Key"], "secret-key")
        XCTAssertNil(stitchConfig?["headersHelper"], "Non-OAuth HTTP servers with static headers must not attach headersHelper")

        let settingsData = try Data(contentsOf: PathConstants.claudeSettingsFile)
        let settingsJson = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        XCTAssertEqual(settingsJson?["disableClaudeAiConnectors"] as? Bool, false, "Connectors are the user's choice")
        XCTAssertEqual((settingsJson?["enabledPlugins"] as? [String: Bool])?["browser-use@synced"], true, "Plugins are the user's choice")
        XCTAssertNil(settingsJson?["enableAllProjectMcpServers"], "SyncEngine must never bypass Claude Code MCP approval prompts")

        let cacheData = try Data(contentsOf: authCache)
        let cacheJson = try JSONSerialization.jsonObject(with: cacheData) as? [String: Any]
        XCTAssertNil(cacheJson?["mobbin"], "Stale cache entry for OAuth-backed server must be cleared")
        XCTAssertNotNil(cacheJson?["unrelated-oauth"], "Unrelated auth cache entries must be preserved")

        XCTAssertTrue(
            fm.fileExists(atPath: PathConstants.claudeMCPOAuthHelperScript.path),
            "ensureClaudeEnvironment must self-heal and create mcp-oauth-headers.py on disk when OAuth servers exist"
        )
        XCTAssertTrue(
            fm.isExecutableFile(atPath: PathConstants.claudeMCPOAuthHelperScript.path),
            "mcp-oauth-headers.py must have executable permissions"
        )
    }

    // MARK: - 10. OAuth Headers Helper Performs Live Token Refresh and Static Fallback
    func testMcpOAuthHeadersHelperRefreshesExpiredTokenAndPersistsAtomically() async throws {
        await syncEngine.ensureClaudeEnvironment()
        let scriptPath = PathConstants.claudeMCPOAuthHelperScript.path
        XCTAssertTrue(fm.isExecutableFile(atPath: scriptPath))

        let oauthFile = tempDir.appendingPathComponent("test_mcp_oauth_tokens.json")
        let runnerScript = tempDir.appendingPathComponent("run_refresh_test.py")
        let runnerCode = """
        import base64, json, os, subprocess, sys, threading, time
        from http.server import BaseHTTPRequestHandler, HTTPServer

        script_path = sys.argv[1]
        oauth_file = sys.argv[2]

        def make_jwt(exp_ts):
            hdr = base64.urlsafe_b64encode(b'{"alg":"HS256","typ":"JWT"}').decode().rstrip("=")
            pld = base64.urlsafe_b64encode(json.dumps({"exp": exp_ts}).encode()).decode().rstrip("=")
            return f"{hdr}.{pld}.sig"

        expired_jwt = make_jwt(int(time.time()) - 600)
        fresh_jwt = make_jwt(int(time.time()) + 3600)

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length).decode()
                assert "grant_type=refresh_token" in body
                assert "refresh_token=old-refresh-tok" in body
                assert "client_id=test-client-123" in body
                resp = json.dumps({
                    "access_token": fresh_jwt,
                    "refresh_token": "new-refresh-tok",
                    "token_type": "Bearer",
                    "expires_in": 3600
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(resp)))
                self.end_headers()
                self.wfile.write(resp)
            def log_message(self, format, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        port = server.server_port
        t = threading.Thread(target=server.handle_request, daemon=True)
        t.start()

        initial_payload = {
            "https://api.mobbin.com/mcp": {
                "server_url": "https://api.mobbin.com/mcp",
                "token_url": f"http://127.0.0.1:{port}/oauth/token",
                "client_id": "test-client-123",
                "token": {
                    "access_token": expired_jwt,
                    "refresh_token": "old-refresh-tok",
                    "token_type": "Bearer",
                    "expiry": "2020-01-01T00:00:00+00:00"
                }
            }
        }
        with open(oauth_file, "w") as f:
            json.dump(initial_payload, f)

        env = dict(os.environ)
        env["CLAUDE_CODE_MCP_SERVER_URL"] = "https://api.mobbin.com/mcp"
        env["CLAUDE_CODE_MCP_SERVER_NAME"] = "mobbin"
        env["CLAUDE_CODE_MCP_OAUTH_FILE"] = oauth_file

        out = subprocess.check_output([script_path], env=env).decode().strip()
        parsed_out = json.loads(out)
        assert parsed_out.get("Authorization") == f"Bearer {fresh_jwt}", f"Unexpected output: {out}"

        with open(oauth_file, "r") as f:
            persisted = json.load(f)["https://api.mobbin.com/mcp"]["token"]
        assert persisted["access_token"] == fresh_jwt
        assert persisted["refresh_token"] == "new-refresh-tok"
        print("REFRESH_OK")
        """
        try runnerCode.write(to: runnerScript, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [runnerScript.path, scriptPath, oauthFile.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(proc.terminationStatus, 0, "Refresh helper test failed: \(output)")
        XCTAssertTrue(output.contains("REFRESH_OK"), "Expected REFRESH_OK in output: \(output)")
    }

    // MARK: - 11. VaultService Merges Missing Headers Into Existing Server Definition
    func testVaultServiceMergesMissingHeadersIntoExistingServer() async throws {
        let vaultService = VaultService()
        await vaultService.initializeVaultIfNeeded()

        // 1. Save supabase initially WITHOUT headers in master_mcp.json
        let initialSupabase = MCPServerDefinition(
            id: "supabase",
            name: "supabase",
            category: "Database",
            config: ["serverUrl": .string("https://mcp.supabase.com/mcp")]
        )
        await vaultService.saveServers([initialSupabase])

        // 2. Write global mcp_config.json where supabase has Authorization header
        let globalConfigDir = PathConstants.globalConfigDirectory
        try fm.createDirectory(at: globalConfigDir, withIntermediateDirectories: true)
        let globalPayload: [String: Any] = [
            "mcpServers": [
                "supabase": [
                    "serverUrl": "https://mcp.supabase.com/mcp",
                    "headers": ["Authorization": "Bearer sbp_test_token_123"],
                    "disabled": false
                ]
            ]
        ]
        let globalData = try JSONSerialization.data(withJSONObject: globalPayload, options: [.prettyPrinted])
        try globalData.write(to: PathConstants.globalMCPConfigFile)

        // 3. Scan and ingest -> must merge missing Authorization header into master_mcp.json
        let (rescanned, _) = await vaultService.scanAndIngestServers()
        let updatedSupabase = rescanned.first(where: { $0.id == "supabase" })
        let authHeader = updatedSupabase?.config["headers"]?.objectValue?["Authorization"]?.stringValue
        XCTAssertEqual(authHeader, "Bearer sbp_test_token_123", "VaultService must ingest missing headers into existing server entry")
    }
}

