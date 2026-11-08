import XCTest
@testable import AntigravityManager

@MainActor
final class M4_2ChallengerAdversarialTests: XCTestCase {
    private var testSandboxDir: URL!
    private let fm = FileManager.default
    private var syncEngine: SyncEngine!
    private var state: AppState!

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("M4_2Challenger_\(UUID().uuidString)", isDirectory: true)
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
        state = AppState(autoload: false)
        await state.vaultService.initializeVaultIfNeeded()
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

    // MARK: - 1. Terminal Launching & Resolution Verification (R4.4)

    func testTerminalResolutionDoesNotTargetFinder() {
        // Requirement R4.4: Ensure openTerminal resolves Terminal.app, NOT Finder.app
        let terminalBundleId = "com.apple.Terminal"
        let resolvedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleId)
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

        XCTAssertNotNil(resolvedURL, "Terminal.app must be resolvable on macOS")
        XCTAssertTrue(fm.fileExists(atPath: resolvedURL.path), "Terminal.app must exist at \(resolvedURL.path)")

        // Assert it does NOT resolve to Finder
        let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        XCTAssertNotEqual(resolvedURL, finderURL, "Terminal resolution must never resolve to Finder.app")

        if let bundle = Bundle(url: resolvedURL) {
            XCTAssertEqual(bundle.bundleIdentifier, "com.apple.Terminal", "Resolved application must have bundle identifier com.apple.Terminal")
        }
    }

    func testOpenTerminalGracefulExecutionOnVariousPaths() {
        let validProjectDir = testSandboxDir.appendingPathComponent("Projects/ValidProj", isDirectory: true)
        try? fm.createDirectory(at: validProjectDir, withIntermediateDirectories: true)

        // 1. Valid directory path
        state.openTerminal(for: validProjectDir.path)
        XCTAssertEqual(state.statusMessage, "Terminal ready for: ValidProj")

        // 2. Non-existent path
        state.openTerminal(for: "/tmp/non_existent_folder_xyz_\(UUID().uuidString)")
        XCTAssertEqual(state.statusMessage, "Project folder does not exist at the specified path")

        // 3. Empty string
        state.openTerminal(for: "")
        XCTAssertEqual(state.statusMessage, "Project folder does not exist at the specified path")

        // 4. Whitespace string
        state.openTerminal(for: "    ")
        XCTAssertEqual(state.statusMessage, "Project folder does not exist at the specified path")
    }

    // MARK: - 2. Vault Skill Creation & Frontmatter Parsing (R4.3)

    func testCreateVaultSkillGeneratesStandardFrontmatterAndIsScannable() async throws {
        let skillName = "Advanced Code Reviewer"
        let skillDesc = "Performs adversarial multi-agent code analysis and finds subtle race conditions."
        let skillCategory = "Multi-Agent & Review"

        let created = try await state.createVaultSkill(
            id: "  advanced-code-reviewer  ",
            name: skillName,
            description: skillDesc,
            category: skillCategory
        )

        XCTAssertEqual(created.id, "advanced-code-reviewer")
        XCTAssertEqual(created.name, skillName)
        XCTAssertEqual(created.category, skillCategory)
        XCTAssertEqual(created.origin, .vault)

        // Verify folder and SKILL.md on disk
        let skillFolder = PathConstants.vaultSkillsDirectory.appendingPathComponent("advanced-code-reviewer", isDirectory: true)
        XCTAssertTrue(fm.fileExists(atPath: skillFolder.path), "Skill folder must exist in Master Vault")

        let skillMdFile = skillFolder.appendingPathComponent("SKILL.md")
        XCTAssertTrue(fm.fileExists(atPath: skillMdFile.path), "SKILL.md must exist in skill folder")

        let content = try String(contentsOf: skillMdFile, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("---\n"), "SKILL.md must begin with YAML frontmatter delimiter")
        XCTAssertTrue(content.contains("name: \(skillName)\n"), "YAML frontmatter must contain skill name")
        XCTAssertTrue(content.contains("description: \(skillDesc)\n"), "YAML frontmatter must contain skill description")
        XCTAssertTrue(content.contains("---\n\n# \(skillName)"), "SKILL.md must include markdown body after frontmatter")

        // Verify that SkillScannerService parses this exact SKILL.md file and extracts the description
        let scanner = SkillScannerService()
        let scannedSkills = scanner.scanVaultSkills()
        guard let scanned = scannedSkills.first(where: { $0.id == "advanced-code-reviewer" }) else {
            XCTFail("Scanned vault skills must contain newly created skill")
            return
        }
        XCTAssertEqual(scanned.description, skillDesc, "SkillScannerService must parse the description from frontmatter")

        // Verify state reactivity & sync history
        XCTAssertTrue(state.skills.contains(where: { $0.id == "advanced-code-reviewer" }))
        XCTAssertTrue(state.syncHistory.contains(where: { $0.category == .vault && $0.status == .success }))
        XCTAssertTrue(state.statusMessage?.contains(skillName) == true)
    }

    func testCreateVaultSkillWithCustomInitialContent() async throws {
        let customContent = """
        ---
        name: Custom Frontmatter Skill
        description: Custom frontmatter description that is multi-line
        version: 3.1.4
        author: Challenger
        ---

        # Custom Frontmatter Skill

        Detailed instructions for the agent.
        """

        let created = try await state.createVaultSkill(
            id: "custom-frontmatter-skill",
            name: "Custom Frontmatter Skill",
            description: "Ignored description when initialContent is provided",
            category: "Core & Tools",
            initialContent: customContent
        )

        XCTAssertEqual(created.id, "custom-frontmatter-skill")

        let skillMd = PathConstants.vaultSkillsDirectory
            .appendingPathComponent("custom-frontmatter-skill")
            .appendingPathComponent("SKILL.md")
        let fileContent = try String(contentsOf: skillMd, encoding: .utf8)
        XCTAssertEqual(fileContent, customContent, "Custom initial content must be written verbatim to SKILL.md")

        let scanner = SkillScannerService()
        let scanned = scanner.scanVaultSkills().first(where: { $0.id == "custom-frontmatter-skill" })
        XCTAssertEqual(scanned?.description, "Custom frontmatter description that is multi-line")
    }

    func testCreateVaultSkillRejectsEmptyOrWhitespaceId() async {
        do {
            _ = try await state.createVaultSkill(id: "", name: "Empty ID", description: "Desc")
            XCTFail("Empty skill ID must throw error")
        } catch let err as NSError {
            XCTAssertEqual(err.domain, "SkillCreation")
            XCTAssertEqual(err.code, 1)
            XCTAssertTrue(err.localizedDescription.contains("cannot be empty"))
        }

        do {
            _ = try await state.createVaultSkill(id: "   \n\t  ", name: "Whitespace ID", description: "Desc")
            XCTFail("Whitespace skill ID must throw error")
        } catch let err as NSError {
            XCTAssertEqual(err.code, 1)
        }
    }

    func testCreateVaultSkillRejectsCollisionAndProtectsExistingFiles() async throws {
        let skillFolder = PathConstants.vaultSkillsDirectory.appendingPathComponent("protected-skill", isDirectory: true)
        try fm.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        let canaryFile = skillFolder.appendingPathComponent("canary.txt")
        try "CRITICAL_PREEXISTING_DATA".write(to: canaryFile, atomically: true, encoding: .utf8)

        do {
            _ = try await state.createVaultSkill(
                id: "protected-skill",
                name: "Protected Skill Attempt",
                description: "Overwriting attempt"
            )
            XCTFail("Creating skill with existing folder ID must throw collision error")
        } catch let err as NSError {
            XCTAssertEqual(err.domain, "SkillCreation")
            XCTAssertEqual(err.code, 2)
            XCTAssertTrue(err.localizedDescription.contains("already exists"))
        }

        // Verify pre-existing data was NOT destroyed or overwritten
        let canaryContent = try String(contentsOf: canaryFile, encoding: .utf8)
        XCTAssertEqual(canaryContent, "CRITICAL_PREEXISTING_DATA", "Pre-existing files must be protected upon collision")
    }

    // MARK: - 3. Stdio & Remote MCP Server Management (R4.3)

    func testSaveServerStdioWithMultilineArgsAndComplexEnv() async throws {
        let multilineArgs = [
            "-y",
            "@modelcontextprotocol/server-postgres",
            "postgresql://user:p%40ss@localhost:5432/mydb?sslmode=disable",
            "--schema",
            "public,audit"
        ]

        let complexEnv: [String: JSONValue] = [
            "PG_SSL": .string("false"),
            "CONN_STR": .string("host=127.0.0.1;port=5432;db=test;pwd=secret=123="), // Contains multiple '='
            "SPECIAL_CHARS": .string("val with spaces and $#@! & symbols")
        ]

        let server = MCPServerDefinition(
            id: "postgres-stdio",
            name: "PostgreSQL Local Stdio",
            category: "Database",
            config: [
                "command": .string("npx"),
                "args": .array(multilineArgs.map { .string($0) }),
                "env": .object(complexEnv)
            ]
        )

        await state.saveServer(server, enableGlobally: true)

        // 1. Verify in-memory state
        guard let inMemory = state.servers.first(where: { $0.id == "postgres-stdio" }) else {
            XCTFail("Server must exist in state.servers")
            return
        }
        XCTAssertEqual(inMemory.command, "npx")
        XCTAssertFalse(inMemory.isRemote)
        XCTAssertEqual(inMemory.category, "Database")
        XCTAssertTrue(state.globalServerIds.contains("postgres-stdio"), "Server should be active globally")

        // Check args
        let savedArgs = inMemory.config["args"]?.arrayValue?.compactMap { $0.stringValue }
        XCTAssertEqual(savedArgs, multilineArgs)

        // Check complex env
        let savedEnv = inMemory.config["env"]?.objectValue
        XCTAssertEqual(savedEnv?["CONN_STR"]?.stringValue, "host=127.0.0.1;port=5432;db=test;pwd=secret=123=")

        // 2. Verify Master Vault persistence
        let vaultServers = await state.vaultService.loadServers()
        guard let vaultServer = vaultServers.first(where: { $0.id == "postgres-stdio" }) else {
            XCTFail("Server must be persisted in Master Vault")
            return
        }
        XCTAssertEqual(vaultServer.name, "PostgreSQL Local Stdio")
        XCTAssertEqual(vaultServer.config["args"]?.arrayValue?.compactMap { $0.stringValue }, multilineArgs)

        // 3. Verify Global Config persistence via SyncEngine
        try await syncEngine.syncGlobalConfig(servers: state.servers, enabledIds: state.globalServerIds)
        let globalConfigData = try Data(contentsOf: PathConstants.globalMCPConfigFile)
        guard let globalJson = try JSONSerialization.jsonObject(with: globalConfigData) as? [String: Any],
              let serversDict = globalJson["mcpServers"] as? [String: Any],
              let postgresEntry = serversDict["postgres-stdio"] as? [String: Any] else {
            XCTFail("global config must contain postgres-stdio")
            return
        }
        XCTAssertEqual(postgresEntry["disabled"] as? Bool, false, "Globally enabled server must have disabled: false")
        XCTAssertEqual(postgresEntry["command"] as? String, "npx")
    }

    func testSaveServerRemoteWithHeadersAndSwitchFromStdio() async throws {
        // Step 1: Create a stdio server
        let initialStdio = MCPServerDefinition(
            id: "custom-api-server",
            name: "Initial Stdio Server",
            category: "Cloud",
            config: [
                "command": .string("uvx"),
                "args": .array([.string("mcp-server-api")]),
                "env": .object(["PORT": .string("8080")])
            ]
        )
        await state.saveServer(initialStdio, enableGlobally: false)
        XCTAssertFalse(state.globalServerIds.contains("custom-api-server"))

        // Step 2: Edit server to Remote SSE with HTTP headers
        let remoteHeaders: [String: JSONValue] = [
            "Authorization": .string("Bearer secret_jwt_token_12345"),
            "X-Tenant-ID": .string("tenant-prod-99"),
            "Accept": .string("text/event-stream")
        ]
        let remoteServer = MCPServerDefinition(
            id: "custom-api-server",
            name: "Updated Remote Server",
            category: "Cloud",
            config: [
                "serverUrl": .string("https://api.mycloud.io/mcp/sse"),
                "headers": .object(remoteHeaders)
            ]
        )
        await state.saveServer(remoteServer, enableGlobally: false)

        // Verify count didn't duplicate
        let matchingServers = state.servers.filter { $0.id == "custom-api-server" }
        XCTAssertEqual(matchingServers.count, 1, "Editing a server must replace existing item, not duplicate it")

        // Verify remote properties
        let updated = matchingServers[0]
        XCTAssertTrue(updated.isRemote)
        XCTAssertEqual(updated.serverUrl, "https://api.mycloud.io/mcp/sse")
        XCTAssertNil(updated.command, "command must be nil when converted to remote")
        XCTAssertNil(updated.config["args"], "args must be cleaned up when converted to remote")
        XCTAssertNil(updated.config["env"], "env must be cleaned up when converted to remote")

        let loadedHeaders = updated.config["headers"]?.objectValue
        XCTAssertEqual(loadedHeaders?["Authorization"]?.stringValue, "Bearer secret_jwt_token_12345")
        XCTAssertEqual(loadedHeaders?["X-Tenant-ID"]?.stringValue, "tenant-prod-99")

        // Verify Master Vault persistence
        let vaultServers = await state.vaultService.loadServers()
        let loadedVault = vaultServers.first(where: { $0.id == "custom-api-server" })
        XCTAssertEqual(loadedVault?.serverUrl, "https://api.mycloud.io/mcp/sse")
        XCTAssertNil(loadedVault?.command)

        // Verify Global Config marks it disabled when enableGlobally is false
        try await syncEngine.syncGlobalConfig(servers: state.servers, enabledIds: state.globalServerIds)
        let globalConfigData = try Data(contentsOf: PathConstants.globalMCPConfigFile)
        guard let globalJson = try JSONSerialization.jsonObject(with: globalConfigData) as? [String: Any],
              let serversDict = globalJson["mcpServers"] as? [String: Any],
              let entry = serversDict["custom-api-server"] as? [String: Any] else {
            XCTFail("global config must contain custom-api-server")
            return
        }
        XCTAssertEqual(entry["disabled"] as? Bool, true, "Server saved with enableGlobally: false must have disabled: true")
        XCTAssertEqual(entry["serverUrl"] as? String, "https://api.mycloud.io/mcp/sse")
    }

    func testGlobalCoreEnablementMatrixPersistence() async throws {
        // Test two servers: one enabled globally, one disabled globally
        let s1 = MCPServerDefinition(id: "global-active-1", name: "G1", category: "Tools", config: ["command": .string("npx")])
        let s2 = MCPServerDefinition(id: "global-inactive-2", name: "G2", category: "Tools", config: ["command": .string("npx")])

        await state.saveServer(s1, enableGlobally: true)
        await state.saveServer(s2, enableGlobally: false)

        XCTAssertTrue(state.globalServerIds.contains("global-active-1"))
        XCTAssertFalse(state.globalServerIds.contains("global-inactive-2"))

        // Run sync
        try await syncEngine.syncGlobalConfig(servers: state.servers, enabledIds: state.globalServerIds)
        let globalConfigData = try Data(contentsOf: PathConstants.globalMCPConfigFile)
        let globalJson = try JSONSerialization.jsonObject(with: globalConfigData) as! [String: Any]
        let serversDict = globalJson["mcpServers"] as! [String: Any]

        let s1Dict = serversDict["global-active-1"] as! [String: Any]
        let s2Dict = serversDict["global-inactive-2"] as! [String: Any]

        XCTAssertEqual(s1Dict["disabled"] as? Bool, false)
        XCTAssertEqual(s2Dict["disabled"] as? Bool, true)
    }

    // MARK: - 4. Additional Adversarial & Edge Cases (R4.3 & R4.4)

    func testCreateVaultSkillEdgeCasesNameFallbackAndCategoryGuess() async throws {
        // Test empty name falls back to ID
        let skill1 = try await state.createVaultSkill(
            id: "auto-named-skill",
            name: "   \n\t ",
            description: "Some description",
            category: nil // Should guess
        )
        XCTAssertEqual(skill1.name, "auto-named-skill", "Empty name should fall back to clean ID")
        XCTAssertEqual(skill1.category, "Core & Tools", "Guessed category for generic ID should be Core & Tools")

        // Test category guessing for Apple / Swift ID
        let skill2 = try await state.createVaultSkill(
            id: "swiftui-animations",
            name: "",
            description: "Apple animation patterns",
            category: nil
        )
        XCTAssertEqual(skill2.category, "Swift & Apple", "ID with swift should guess Swift & Apple category")

        // Test custom category preservation
        let skill3 = try await state.createVaultSkill(
            id: "custom-cat-skill",
            name: "Custom Cat Skill",
            description: "Custom cat",
            category: "Enterprise Workflows"
        )
        XCTAssertEqual(skill3.category, "Enterprise Workflows", "Explicit category should be preserved")
    }

    func testEditMCPServerArgsAndEnvParsingFidelity() async throws {
        // Test raw argsText with mixed empty lines, carriage returns, and spaces
        let rawArgsText = """
        -y
           
        @org/mcp-server-test

        --verbose
           --config-file /etc/mcp.conf   
        """

        let parsedArgs = rawArgsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        XCTAssertEqual(parsedArgs, [
            "-y",
            "@org/mcp-server-test",
            "--verbose",
            "--config-file /etc/mcp.conf"
        ], "Empty lines and padding should be stripped cleanly")

        // Test env pairs with empty keys and values with '='
        let pairs: [(key: String, value: String)] = [
            ("KEY_VALID", "simple_value"),
            ("   ", "ignored_empty_key"),
            ("DATABASE_URL", "postgres://user:pass=secret@localhost:5432/db?sslmode=disable&opt=1"),
            ("TOKEN", "Bearer xyz===")
        ]

        var envDict: [String: JSONValue] = [:]
        for pair in pairs where !pair.key.trimmingCharacters(in: .whitespaces).isEmpty {
            envDict[pair.key.trimmingCharacters(in: .whitespaces)] = .string(pair.value)
        }

        XCTAssertEqual(envDict.count, 3, "Empty keys must be omitted")
        XCTAssertEqual(envDict["DATABASE_URL"]?.stringValue, "postgres://user:pass=secret@localhost:5432/db?sslmode=disable&opt=1")
        XCTAssertEqual(envDict["TOKEN"]?.stringValue, "Bearer xyz===")

        let server = MCPServerDefinition(
            id: "fidelity-test-server",
            name: "Fidelity Server",
            category: "Database",
            config: [
                "command": .string("npx"),
                "args": .array(parsedArgs.map { .string($0) }),
                "env": .object(envDict)
            ]
        )

        await state.saveServer(server, enableGlobally: false)

        let loaded = state.servers.first(where: { $0.id == "fidelity-test-server" })
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.config["args"]?.arrayValue?.count, 4)
        XCTAssertEqual(loaded?.config["env"]?.objectValue?["DATABASE_URL"]?.stringValue, "postgres://user:pass=secret@localhost:5432/db?sslmode=disable&opt=1")
    }

    func testOpenTerminalWithUnicodeAndSpacesPath() {
        let unicodeDir = testSandboxDir.appendingPathComponent("Projects/Project Ümlaut Café 🚀 123", isDirectory: true)
        try? fm.createDirectory(at: unicodeDir, withIntermediateDirectories: true)

        // Ensure path with spaces and Unicode executes safely
        state.openTerminal(for: unicodeDir.path)
        XCTAssertNotNil(state)
    }

    func testSaveServerUpdateInPlaceDoesNotDuplicate() async {
        let s = MCPServerDefinition(id: "unique-server", name: "Version 1", category: "Tools", config: ["command": .string("npx")])
        await state.saveServer(s, enableGlobally: false)
        let initialCount = state.servers.count

        let sUpdated = MCPServerDefinition(id: "unique-server", name: "Version 2", category: "Analytics", config: ["command": .string("uvx")])
        await state.saveServer(sUpdated, enableGlobally: false)

        XCTAssertEqual(state.servers.count, initialCount, "Updating an existing server must not change servers array count")
        let found = state.servers.first(where: { $0.id == "unique-server" })
        XCTAssertEqual(found?.name, "Version 2")
        XCTAssertEqual(found?.category, "Analytics")
        XCTAssertEqual(found?.command, "uvx")
    }
}
