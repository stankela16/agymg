import XCTest
@testable import AntigravityManager

final class V1_0_1AuditRegressionTests: XCTestCase {
    private var sandboxDir: URL!
    private let fm = FileManager.default
    private var syncEngine: SyncEngine!

    override func setUp() {
        super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("V1_0_1AuditTests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        sandboxDir = dir
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
        if let dir = sandboxDir {
            try? fm.removeItem(at: dir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    // MARK: - P0 #1: Never delete or overwrite physical ~/.claude/CLAUDE.md, preserve existing symlinks
    func testPhysicalClaudeMemoryFileIsNeverOverwrittenWhileExistingSymlinkIsPreserved() async throws {
        let geminiMemory = PathConstants.geminiDirectory.appendingPathComponent("GEMINI.md")
        try "# Antigravity Memory".write(to: geminiMemory, atomically: true, encoding: .utf8)

        let claudeDir = PathConstants.claudeDirectory
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let claudeMemory = claudeDir.appendingPathComponent("CLAUDE.md")
        try "# Precious Physical Claude Memory".write(to: claudeMemory, atomically: true, encoding: .utf8)

        let server = MCPServerDefinition(
            id: "demo-srv",
            name: "Demo",
            category: "Core",
            config: ["command": .string("node")]
        )
        try await syncEngine.syncGlobalConfig(servers: [server], enabledIds: ["demo-srv"])
        try await syncEngine.syncGlobalSkills(allSkills: [], enabledSkillIds: [])

        let isPhysicalSymlink = await syncEngine.isSymlink(at: claudeMemory)
        XCTAssertFalse(isPhysicalSymlink, "Physical CLAUDE.md must never be replaced with a symlink")
        let content = try String(contentsOf: claudeMemory, encoding: .utf8)
        XCTAssertEqual(content, "# Precious Physical Claude Memory")

        // Now verify an existing user symlink ~/.claude/CLAUDE.md -> ~/.gemini/GEMINI.md remains intact
        try fm.removeItem(at: claudeMemory)
        try fm.createSymbolicLink(at: claudeMemory, withDestinationURL: geminiMemory)
        try await syncEngine.syncGlobalConfig(servers: [server], enabledIds: ["demo-srv"])

        let isStillSymlink = await syncEngine.isSymlink(at: claudeMemory)
        XCTAssertTrue(isStillSymlink, "Existing user symlink for CLAUDE.md must remain intact")
        XCTAssertEqual(
            try fm.destinationOfSymbolicLink(atPath: claudeMemory.path),
            geminiMemory.path
        )
    }

    // MARK: - P0 #2: Never inject enableAllProjectMcpServers or hasTrustDialogAccepted
    func testSyncNeverBypassesClaudeSecurityPrompts() async throws {
        let projectURL = sandboxDir.appendingPathComponent("Projects/sec-repo", isDirectory: true)
        try fm.createDirectory(at: projectURL.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)

        let server = MCPServerDefinition(
            id: "srv-1",
            name: "Server 1",
            category: "Core",
            config: ["command": .string("npx"), "args": .array([.string("srv-1")])]
        )
        let project = ProjectProfile(
            id: "sec-repo",
            name: "sec-repo",
            path: projectURL.path,
            enabledMCPServerIds: ["srv-1"],
            enabledSkillIds: [],
            enabledPluginIds: []
        )

        try await syncEngine.syncGlobalConfig(servers: [server], enabledIds: ["srv-1"])
        try await syncEngine.syncProject(project: project, allServers: [server], allSkills: [], allPlugins: [])

        if fm.fileExists(atPath: PathConstants.claudeSettingsFile.path),
           let settingsData = try? Data(contentsOf: PathConstants.claudeSettingsFile),
           let settingsJSON = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
            XCTAssertNil(settingsJSON["enableAllProjectMcpServers"])
        }

        let claudeData = try Data(contentsOf: PathConstants.claudeConfigFile)
        let claudeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: claudeData) as? [String: Any])
        let projectsDict = try XCTUnwrap(claudeJSON["projects"] as? [String: [String: Any]])
        let projEntry = try XCTUnwrap(projectsDict[projectURL.path])
        XCTAssertNil(projEntry["hasTrustDialogAccepted"], "hasTrustDialogAccepted must never be set automatically")
        XCTAssertNotNil(projEntry["mcpServers"])
    }

    // MARK: - P1 #3: Conditional .gitignore modification (requires .git AND non-empty enabledMCPServerIds)
    func testGitignoreOnlyModifiedWhenGitRepoAndMCPServersEnabled() async throws {
        let server = MCPServerDefinition(
            id: "pg",
            name: "Postgres",
            category: "Database",
            config: ["command": .string("npx")]
        )

        // Case A: Non-git folder with enabled MCP server -> must NOT create .gitignore
        let nonGitURL = sandboxDir.appendingPathComponent("Projects/non-git-folder", isDirectory: true)
        try fm.createDirectory(at: nonGitURL, withIntermediateDirectories: true)
        let nonGitProject = ProjectProfile(
            id: "non-git",
            name: "non-git",
            path: nonGitURL.path,
            enabledMCPServerIds: ["pg"]
        )
        try await syncEngine.syncProject(project: nonGitProject, allServers: [server], allSkills: [], allPlugins: [])
        XCTAssertFalse(
            fm.fileExists(atPath: nonGitURL.appendingPathComponent(".gitignore").path),
            "Non-git folders must not have .gitignore created"
        )
        XCTAssertTrue(fm.fileExists(atPath: nonGitURL.appendingPathComponent(".agents/plugins/agy-manager/mcp_config.json").path))

        // Case B: Git repo with 0 enabled MCP servers -> must NOT create or dirty .gitignore
        let emptyGitURL = sandboxDir.appendingPathComponent("Projects/empty-git-repo", isDirectory: true)
        try fm.createDirectory(at: emptyGitURL.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
        let existingIgnore = emptyGitURL.appendingPathComponent(".gitignore")
        try "dist/\n".write(to: existingIgnore, atomically: true, encoding: .utf8)
        let emptyGitProject = ProjectProfile(
            id: "empty-git",
            name: "empty-git",
            path: emptyGitURL.path,
            enabledMCPServerIds: []
        )
        try await syncEngine.syncProject(project: emptyGitProject, allServers: [server], allSkills: [], allPlugins: [])
        XCTAssertEqual(
            try String(contentsOf: existingIgnore, encoding: .utf8),
            "dist/\n",
            "Git repo without enabled project MCP servers must not have .gitignore modified"
        )

        // Case C: Git repo WITH enabled MCP server -> MUST protect .agents/plugins/agy-manager/
        let activeGitURL = sandboxDir.appendingPathComponent("Projects/active-git-repo", isDirectory: true)
        try fm.createDirectory(at: activeGitURL.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
        let activeProject = ProjectProfile(
            id: "active-git",
            name: "active-git",
            path: activeGitURL.path,
            enabledMCPServerIds: ["pg"]
        )
        try await syncEngine.syncProject(project: activeProject, allServers: [server], allSkills: [], allPlugins: [])
        let activeIgnore = try String(contentsOf: activeGitURL.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(activeIgnore.contains(".agents/plugins/agy-manager/"))
    }

    // MARK: - P1 #4: Never delete physical directories on sync/purge & block path traversal IDs
    func testPathTraversalRejectionAndPhysicalDirectoryPreservation() async throws {
        XCTAssertFalse(PathConstants.isSafeResourceId(""))
        XCTAssertFalse(PathConstants.isSafeResourceId("."))
        XCTAssertFalse(PathConstants.isSafeResourceId(".."))
        XCTAssertFalse(PathConstants.isSafeResourceId("../escape"))
        XCTAssertFalse(PathConstants.isSafeResourceId("nested/id"))
        XCTAssertFalse(PathConstants.isSafeResourceId("nested\\id"))
        XCTAssertTrue(PathConstants.isSafeResourceId("valid-skill_01.v2"))

        // Physical skill & plugin directories in global, project, and ~/.local/share must survive sync and purge
        let vaultSkill = PathConstants.vaultSkillsDirectory.appendingPathComponent("shared-skill", isDirectory: true)
        try fm.createDirectory(at: vaultSkill, withIntermediateDirectories: true)
        try "---\nname: shared-skill\n---\nVault version".write(
            to: vaultSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let physicalClaudeSkill = PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent("shared-skill", isDirectory: true)
        try fm.createDirectory(at: physicalClaudeSkill, withIntermediateDirectories: true)
        try "Physical Claude skill".write(
            to: physicalClaudeSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let projectURL = sandboxDir.appendingPathComponent("Projects/phys-repo", isDirectory: true)
        let committedSkill = projectURL.appendingPathComponent(".claude/skills/shared-skill", isDirectory: true)
        try fm.createDirectory(at: committedSkill, withIntermediateDirectories: true)
        try "Committed repo skill".write(
            to: committedSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let localShareMCP = PathConstants.effectiveHomeDirectory.appendingPathComponent(".local/share/demo-mcp", isDirectory: true)
        try fm.createDirectory(at: localShareMCP, withIntermediateDirectories: true)
        let localShareMarker = localShareMCP.appendingPathComponent("venv.marker")
        try "keep".write(to: localShareMarker, atomically: true, encoding: .utf8)

        let skillDef = SkillDefinition(
            id: "shared-skill",
            name: "shared-skill",
            description: "desc",
            path: vaultSkill.appendingPathComponent("SKILL.md").path
        )
        let proj = ProjectProfile(id: "phys-repo", name: "phys-repo", path: projectURL.path)

        try await syncEngine.syncGlobalSkills(allSkills: [skillDef], enabledSkillIds: ["shared-skill"])
        try await syncEngine.syncGlobalSkills(allSkills: [skillDef], enabledSkillIds: [])
        await syncEngine.purgeSkillCompletely(id: "shared-skill", allProjects: [proj])
        try await syncEngine.purgeServerCompletely(id: "demo", allProjects: [proj])

        XCTAssertTrue(fm.fileExists(atPath: physicalClaudeSkill.appendingPathComponent("SKILL.md").path))
        XCTAssertEqual(try String(contentsOf: physicalClaudeSkill.appendingPathComponent("SKILL.md"), encoding: .utf8), "Physical Claude skill")
        XCTAssertTrue(fm.fileExists(atPath: committedSkill.appendingPathComponent("SKILL.md").path))
        XCTAssertEqual(try String(contentsOf: committedSkill.appendingPathComponent("SKILL.md"), encoding: .utf8), "Committed repo skill")
        XCTAssertTrue(fm.fileExists(atPath: localShareMarker.path), "purgeServerCompletely must never delete ~/.local/share/<id>-mcp")
    }

    // MARK: - P1 #5: Static Authorization header takes precedence over OAuth headersHelper
    func testStaticAuthorizationHeaderSuppressesOAuthHeadersHelper() async throws {
        let oauthTokensURL = PathConstants.engineMCPOAuthTokensFile
        try fm.createDirectory(at: oauthTokensURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oauthPayload: [String: Any] = [
            "https://mcp.example.com/v1/": [
                "token": ["access_token": "oauth_tok"]
            ]
        ]
        try JSONSerialization.data(withJSONObject: oauthPayload).write(to: oauthTokensURL)

        let staticAuthServer = MCPServerDefinition(
            id: "static-auth",
            name: "Static Auth",
            category: "Cloud",
            config: [
                "serverUrl": .string("https://mcp.example.com/v1"),
                "headers": .object(["Authorization": .string("Bearer pat_static_123")])
            ]
        )

        try await syncEngine.syncGlobalConfig(servers: [staticAuthServer], enabledIds: ["static-auth"])

        let claudeData = try Data(contentsOf: PathConstants.claudeConfigFile)
        let claudeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: claudeData) as? [String: Any])
        let servers = try XCTUnwrap(claudeJSON["mcpServers"] as? [String: [String: Any]])
        let entry = try XCTUnwrap(servers["static-auth"])
        XCTAssertNil(entry["headersHelper"], "Explicit static Authorization header must not be overridden by headersHelper")
        XCTAssertEqual((entry["headers"] as? [String: String])?["Authorization"], "Bearer pat_static_123")
    }

    // MARK: - P1 #6: CLI uninstall --restore converts symlinks back to physical folders & cleans wrappers/hooks
    func testCLIUninstallRestoreConvertsSymlinksAndCleansWrappersSafely() async throws {
        let vault = VaultService()
        await vault.initializeVaultIfNeeded()

        // Create a canonical skill and plugin in Vault
        let vaultSkill = PathConstants.vaultSkillsDirectory.appendingPathComponent("portable-skill", isDirectory: true)
        try fm.createDirectory(at: vaultSkill, withIntermediateDirectories: true)
        try "---\nname: portable-skill\n---\nSkill Body".write(
            to: vaultSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let vaultPlugin = PathConstants.vaultPluginsDirectory.appendingPathComponent("portable-plugin", isDirectory: true)
        let vaultPluginSkill = vaultPlugin.appendingPathComponent("skills/bundled-skill", isDirectory: true)
        try fm.createDirectory(at: vaultPluginSkill, withIntermediateDirectories: true)
        try "{\"name\":\"portable-plugin\"}".write(to: vaultPlugin.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "---\nname: bundled-skill\n---\nBundled".write(to: vaultPluginSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let oauthTokensURL = PathConstants.engineMCPOAuthTokensFile
        try fm.createDirectory(at: oauthTokensURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [
            "https://api.mobbin.com/mcp": ["token": ["access_token": "tok"]]
        ]).write(to: oauthTokensURL)

        let server = MCPServerDefinition(
            id: "mobbin",
            name: "mobbin",
            category: "Design",
            config: ["serverUrl": .string("https://api.mobbin.com/mcp")]
        )
        let skillDef = SkillDefinition(
            id: "portable-skill",
            name: "portable-skill",
            description: "desc",
            path: vaultSkill.appendingPathComponent("SKILL.md").path
        )
        let pluginDef = PluginDefinition(
            id: "portable-plugin",
            name: "portable-plugin",
            description: "desc",
            path: vaultPlugin.path,
            hasMCP: false,
            hasSkills: true
        )

        let repoURL = sandboxDir.appendingPathComponent("Projects/uninstall-repo", isDirectory: true)
        try fm.createDirectory(at: repoURL.appendingPathComponent(".git/info", isDirectory: true), withIntermediateDirectories: true)

        let project = ProjectProfile(
            id: "uninstall-repo",
            name: "uninstall-repo",
            path: repoURL.path,
            enabledMCPServerIds: ["mobbin"],
            enabledSkillIds: ["portable-skill"],
            enabledPluginIds: ["portable-plugin"]
        )
        await vault.saveProjects([project])

        try await syncEngine.syncGlobalConfig(servers: [server], enabledIds: ["mobbin"])
        try await syncEngine.syncGlobalSkills(allSkills: [skillDef], enabledSkillIds: ["portable-skill"])
        try await syncEngine.syncGlobalPlugins(allPlugins: [pluginDef], enabledPluginIds: ["portable-plugin"])
        try await syncEngine.syncProject(project: project, allServers: [server], allSkills: [skillDef], allPlugins: [pluginDef])

        // Also seed a user-created non-Vault symlink (~/.claude/CLAUDE.md -> ~/.gemini/GEMINI.md) and SessionStart hook
        let geminiMem = PathConstants.geminiDirectory.appendingPathComponent("GEMINI.md")
        let claudeMem = PathConstants.claudeDirectory.appendingPathComponent("CLAUDE.md")
        try "# Memo".write(to: geminiMem, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: claudeMem, withDestinationURL: geminiMem)

        let hookSettings: [String: Any] = [
            "hooks": [
                "SessionStart": [
                    [
                        "hooks": [
                            ["type": "command", "command": "agymg hook-session-start --format claude-text"],
                            ["type": "command", "command": "echo custom-user-hook"]
                        ]
                    ]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: hookSettings, options: [.prettyPrinted]).write(to: PathConstants.claudeSettingsFile)

        // Execute CLI uninstall --restore --json
        let result = await CLIRunner.execute(arguments: ["agymg", "uninstall", "--restore", "--json"])
        XCTAssertEqual(result.exitCode, 0, "uninstall --restore failed: \(result.stderr)")

        let summaryData = try XCTUnwrap(result.stdout.data(using: .utf8))
        let summary = try JSONDecoder().decode(UninstallRestoreSummary.self, from: summaryData)
        XCTAssertTrue(summary.removedHelperScript)
        XCTAssertTrue(summary.cleanedClaudeHooks)
        XCTAssertFalse(summary.purgedVault)

        // Global skills & plugins must now be standalone physical directories (NOT symlinks!)
        let globalSkill = PathConstants.globalSkillsDirectory.appendingPathComponent("portable-skill")
        let claudeSkill = PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent("portable-skill")
        let globalPlugin = PathConstants.globalPluginsDirectory.appendingPathComponent("portable-plugin")

        let isGlobalSkillLink = await syncEngine.isSymlink(at: globalSkill)
        let isClaudeSkillLink = await syncEngine.isSymlink(at: claudeSkill)
        let isGlobalPluginLink = await syncEngine.isSymlink(at: globalPlugin)
        XCTAssertFalse(isGlobalSkillLink)
        XCTAssertFalse(isClaudeSkillLink)
        XCTAssertFalse(isGlobalPluginLink)
        XCTAssertTrue(fm.fileExists(atPath: globalSkill.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: claudeSkill.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: globalPlugin.appendingPathComponent("plugin.json").path))

        // Bundled plugin skill symlink inside ~/.claude/skills/bundled-skill must be removed cleanly
        XCTAssertFalse(fm.fileExists(atPath: PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent("bundled-skill").path))

        // Project agy-manager wrapper & project Vault symlinks must be removed
        XCTAssertFalse(fm.fileExists(atPath: repoURL.appendingPathComponent(".agents/plugins/agy-manager").path))
        XCTAssertFalse(fm.fileExists(atPath: repoURL.appendingPathComponent(".agents/skills/portable-skill").path))
        XCTAssertFalse(fm.fileExists(atPath: repoURL.appendingPathComponent(".claude/skills/portable-skill").path))

        // Non-Vault user symlink (CLAUDE.md) must remain untouched
        let isClaudeMemStillLink = await syncEngine.isSymlink(at: claudeMem)
        XCTAssertTrue(isClaudeMemStillLink)

        // Custom user hook in settings.json must survive while agymg hook-session-start is removed
        let updatedSettingsData = try Data(contentsOf: PathConstants.claudeSettingsFile)
        let updatedSettingsStr = try XCTUnwrap(String(data: updatedSettingsData, encoding: .utf8))
        XCTAssertFalse(updatedSettingsStr.contains("hook-session-start"))
        XCTAssertTrue(updatedSettingsStr.contains("custom-user-hook"))

        // headersHelper reference must be removed from ~/.claude.json while mobbin server definition remains
        let claudeConfigStr = try String(contentsOf: PathConstants.claudeConfigFile, encoding: .utf8)
        XCTAssertFalse(claudeConfigStr.contains("mcp-oauth-headers.py"))
        XCTAssertTrue(claudeConfigStr.contains("https://api.mobbin.com/mcp"))
    }

    // MARK: - P2: File permissions (0o600 on secrets, preserved permissions on ~/.claude.json) & deterministic hashing
    func testSecureFilePermissionsAndDeterministicHashing() async throws {
        // 1. Deterministic SHA-256 short hash
        let h1 = PathConstants.stableShortHash("/tmp/example/repo", length: 12)
        let h2 = PathConstants.stableShortHash("/tmp/example/repo", length: 12)
        let h3 = PathConstants.stableShortHash("/tmp/example/other", length: 12)
        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1.count, 12)
        XCTAssertNotEqual(h1, h3)

        // 2. Vault & MCP config permissions
        let vault = VaultService()
        await vault.initializeVaultIfNeeded()
        let server = MCPServerDefinition(
            id: "sec-mcp",
            name: "Secret MCP",
            category: "Security",
            config: [
                "command": .string("node"),
                "env": .object(["API_TOKEN": .string("super_secret_val")])
            ]
        )
        await vault.saveServers([server])

        // Seed ~/.claude.json with custom 0o640 permissions and verify SyncEngine preserves 0o640
        try "{}".write(to: PathConstants.claudeConfigFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: PathConstants.claudeConfigFile.path)

        let repoURL = sandboxDir.appendingPathComponent("Projects/perm-repo", isDirectory: true)
        try fm.createDirectory(at: repoURL, withIntermediateDirectories: true)
        let project = ProjectProfile(id: "perm-repo", name: "perm-repo", path: repoURL.path, enabledMCPServerIds: ["sec-mcp"])

        try await syncEngine.syncGlobalConfig(servers: [server], enabledIds: ["sec-mcp"])
        try await syncEngine.syncProject(project: project, allServers: [server], allSkills: [], allPlugins: [])

        let masterPerms = (try fm.attributesOfItem(atPath: PathConstants.vaultMCPFile.path)[.posixPermissions] as? Int) ?? 0
        let globalPerms = (try fm.attributesOfItem(atPath: PathConstants.globalMCPConfigFile.path)[.posixPermissions] as? Int) ?? 0
        let projMCPPath = repoURL.appendingPathComponent(".agents/plugins/agy-manager/mcp_config.json").path
        let projPerms = (try fm.attributesOfItem(atPath: projMCPPath)[.posixPermissions] as? Int) ?? 0
        let claudePerms = (try fm.attributesOfItem(atPath: PathConstants.claudeConfigFile.path)[.posixPermissions] as? Int) ?? 0

        XCTAssertEqual(masterPerms & 0o777, 0o600)
        XCTAssertEqual(globalPerms & 0o777, 0o600)
        XCTAssertEqual(projPerms & 0o777, 0o600)
        XCTAssertEqual(claudePerms & 0o777, 0o640, "Existing permissions on ~/.claude.json must be preserved")
    }

    // MARK: - P2: SessionStart hook is strictly read-only on uninitialized sandbox & RuntimeManifestPreviewView redacts secrets
    @MainActor
    func testSessionStartHookIsReadOnlyAndManifestRedactsSecrets() async throws {
        // Brand-new empty geminiDir without manager-vault
        let freshRoot = fm.temporaryDirectory.appendingPathComponent("FreshReadOnlyHook_\(UUID().uuidString)", isDirectory: true)
        let freshGemini = freshRoot.appendingPathComponent(".gemini", isDirectory: true)
        let freshWorkspace = freshRoot.appendingPathComponent("workspace", isDirectory: true)
        try fm.createDirectory(at: freshWorkspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: freshRoot) }

        PathConstants.customGeminiDirectory = freshGemini
        let hookResult = await CLIRunner.execute(
            arguments: ["agymg", "hook-session-start", "--format", "claude-text", "--project", freshWorkspace.path],
            currentDirectoryPath: freshWorkspace.path
        )
        XCTAssertEqual(hookResult.exitCode, 0)
        XCTAssertFalse(
            fm.fileExists(atPath: freshGemini.appendingPathComponent("manager-vault").path),
            "hook-session-start must be strictly read-only and never initialize manager-vault on disk"
        )

        // Verify RuntimeManifestPreviewView redacts env, headers, CLI flag tokens, and URL query tokens
        let secretServer = MCPServerDefinition(
            id: "stripe",
            name: "stripe",
            category: "Payments",
            config: [
                "command": .string("npx"),
                "args": .array([.string("-y"), .string("@stripe/mcp"), .string("--api-key"), .string("sk_live_REAL_SECRET"), .string("--token=tok_REAL_2")]),
                "env": .object(["STRIPE_SECRET_KEY": .string("sk_live_ENV_SECRET")]),
                "headers": .object(["Authorization": .string("Bearer hdr_REAL_SECRET")]),
                "serverUrl": .string("https://mcp.stripe.com/v1?api_key=url_REAL_SECRET&mode=test")
            ]
        )
        let previewProj = ProjectProfile(
            id: "acme",
            name: "acme",
            path: "/tmp/acme",
            enabledMCPServerIds: ["stripe"]
        )
        let previewJSON = RuntimeManifestPreviewView.generateManifestJSON(project: previewProj, servers: [secretServer])
        XCTAssertFalse(previewJSON.contains("sk_live_REAL_SECRET"))
        XCTAssertFalse(previewJSON.contains("tok_REAL_2"))
        XCTAssertFalse(previewJSON.contains("sk_live_ENV_SECRET"))
        XCTAssertFalse(previewJSON.contains("hdr_REAL_SECRET"))
        XCTAssertFalse(previewJSON.contains("url_REAL_SECRET"))
        XCTAssertTrue(previewJSON.contains("<REDACTED>"))
        XCTAssertTrue(previewJSON.contains("mode=test"))
    }

    // MARK: - P2: Vault bootstrap converts physical global skills into symlinks and backs up conflicts
    func testBootstrapVaultConvertsGlobalSkillsToSymlinksAndBacksUpConflicts() async throws {
        let globalSkill = PathConstants.globalSkillsDirectory.appendingPathComponent("custom-skill", isDirectory: true)
        try fm.createDirectory(at: globalSkill, withIntermediateDirectories: true)
        try "---\nname: custom-skill\n---\nGlobal Body".write(
            to: globalSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let claudeConflict = PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent("custom-skill", isDirectory: true)
        try fm.createDirectory(at: claudeConflict, withIntermediateDirectories: true)
        try "---\nname: custom-skill\n---\nDiffering Claude Body".write(
            to: claudeConflict.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()

        let isGlobalLink = await syncEngine.isSymlink(at: globalSkill)
        let isClaudeLink = await syncEngine.isSymlink(at: claudeConflict)
        XCTAssertTrue(isGlobalLink, "Bootstrap must convert physical global Antigravity skill into symlink to Vault")
        XCTAssertTrue(isClaudeLink, "Bootstrap must convert physical global Claude skill into symlink to Vault after backup")

        let conflictBackupsDir = PathConstants.vaultBackupsDirectory.appendingPathComponent("bootstrap-skill-conflicts", isDirectory: true)
        let backupItems = (try? fm.contentsOfDirectory(atPath: conflictBackupsDir.path)) ?? []
        XCTAssertFalse(backupItems.isEmpty, "Conflicting Claude skill content must be backed up before symlink replacement")
    }
}
