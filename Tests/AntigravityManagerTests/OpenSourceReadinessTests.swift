import XCTest
@testable import AntigravityManager

@MainActor
final class OpenSourceReadinessTests: XCTestCase {
    private var sandboxDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("OpenSourceReadiness_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        sandboxDir = dir

        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        ProjectFolderAccessManager.shared.resetAuthorization()
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.userDefaultsKey)
    }

    override func tearDown() async throws {
        ProjectFolderAccessManager.shared.resetAuthorization()
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.userDefaultsKey)
        if let sandboxDir {
            try? fm.removeItem(at: sandboxDir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        try await super.tearDown()
    }

    // MARK: - 1. Default Projects Directory Priority & Fallback

    func testResolveDefaultProjectsDirectoryPriorityAndFallback() throws {
        let fakeHome = sandboxDir.appendingPathComponent("fake-home", isDirectory: true)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        // 1. None exist -> fallback to ~/Projects
        XCTAssertEqual(
            PathConstants.resolveDefaultProjectsDirectory(in: fakeHome, fileManager: fm).path,
            fakeHome.appendingPathComponent("Projects", isDirectory: true).path
        )

        // 2. ~/workspace exists -> chosen
        let workspaceDir = fakeHome.appendingPathComponent("workspace", isDirectory: true)
        try fm.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        XCTAssertEqual(
            PathConstants.resolveDefaultProjectsDirectory(in: fakeHome, fileManager: fm).path,
            workspaceDir.path
        )

        // 3. ~/Developer outranks ~/workspace; regular file at ~/Projects is ignored
        let projectsRegularFile = fakeHome.appendingPathComponent("Projects")
        try Data("not a folder".utf8).write(to: projectsRegularFile)
        let developerDir = fakeHome.appendingPathComponent("Developer", isDirectory: true)
        try fm.createDirectory(at: developerDir, withIntermediateDirectories: true)
        XCTAssertEqual(
            PathConstants.resolveDefaultProjectsDirectory(in: fakeHome, fileManager: fm).path,
            developerDir.path
        )

        // 4. ~/Desktop/Projects has top priority when present
        let desktopProjects = fakeHome.appendingPathComponent("Desktop/Projects", isDirectory: true)
        try fm.createDirectory(at: desktopProjects, withIntermediateDirectories: true)
        XCTAssertEqual(
            PathConstants.resolveDefaultProjectsDirectory(in: fakeHome, fileManager: fm).path,
            desktopProjects.path
        )
    }

    // MARK: - 2. First-Run Onboarding, Skip Mode & Explicit Authorization

    func testProjectFolderAccessManagerFirstRunSkipAndExplicitAuthorization() throws {
        PathConstants.customProjectsDirectory = nil
        let manager = ProjectFolderAccessManager.shared
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.pathKey)

        // Brand-new user: unauthorized, no saved folder
        XCTAssertFalse(manager.isAuthorized, "Brand-new install must default to isAuthorized == false so onboarding is shown")
        XCTAssertFalse(manager.hasSavedFolderAuthorization)
        XCTAssertNil(manager.authorizedDirectoryURL)

        // User clicks "Skip for Now": enters Control Center without authorizing a workspace folder
        manager.isAuthorized = true
        XCTAssertTrue(manager.isAuthorized)
        XCTAssertFalse(manager.hasSavedFolderAuthorization)
        XCTAssertNil(manager.authorizedDirectoryURL, "Skipping folder setup must leave authorizedDirectoryURL nil")

        // User explicitly authorizes a folder
        let chosenDir = sandboxDir.appendingPathComponent("DeveloperRepos", isDirectory: true)
        try fm.createDirectory(at: chosenDir, withIntermediateDirectories: true)
        manager.saveAuthorization(url: chosenDir)

        XCTAssertTrue(manager.isAuthorized)
        XCTAssertTrue(manager.hasSavedFolderAuthorization)
        XCTAssertEqual(
            manager.authorizedDirectoryURL?.resolvingSymlinksInPath().path,
            chosenDir.resolvingSymlinksInPath().path
        )
    }

    // MARK: - 3. Claude Code Project Discovery, Filtering & Collision Disambiguation

    func testProjectScannerDiscoversClaudeProjectsAndFiltersUnsafePaths() throws {
        let repoA = sandboxDir.appendingPathComponent("external/apps/web", isDirectory: true)
        let repoB = sandboxDir.appendingPathComponent("external/packages/web", isDirectory: true)
        let markerlessDir = sandboxDir.appendingPathComponent("external/random-notes", isDirectory: true)
        try fm.createDirectory(at: repoA.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: repoB, withIntermediateDirectories: true)
        try #"{"name":"pkg-web"}"#.write(to: repoB.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: markerlessDir, withIntermediateDirectories: true)

        let claudePayload: [String: Any] = [
            "projects": [
                repoA.path: [
                    "mcpServers": [
                        "stripe-sandbox": ["command": "npx", "args": ["-y", "@stripe/mcp"]]
                    ]
                ],
                repoB.path: [:],
                markerlessDir.path: [:],
                "/": [:],
                "/tmp": [:],
                PathConstants.effectiveHomeDirectory.path: [:],
                PathConstants.geminiDirectory.path: [:],
                PathConstants.claudeDirectory.path: [:]
            ]
        ]
        let claudeData = try JSONSerialization.data(withJSONObject: claudePayload, options: [.prettyPrinted])
        try claudeData.write(to: PathConstants.claudeConfigFile)

        let scanner = ProjectScannerService()
        let discovered = scanner.discoverProjects(in: nil, scanDefaultWhenNil: false)

        let paths = Set(discovered.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path })
        XCTAssertTrue(paths.contains(repoA.resolvingSymlinksInPath().path))
        XCTAssertTrue(paths.contains(repoB.resolvingSymlinksInPath().path))
        XCTAssertFalse(paths.contains(markerlessDir.resolvingSymlinksInPath().path), "Folder without project markers must be ignored")
        XCTAssertFalse(paths.contains("/"))
        XCTAssertFalse(paths.contains("/tmp"))
        XCTAssertEqual(discovered.count, 2)

        // Verify duplicate basename disambiguation ("web" + "packages-web" or "apps-web")
        let uniqueIds = Set(discovered.map(\.id))
        XCTAssertEqual(uniqueIds.count, 2, "Duplicate folder names across parent directories must receive distinct IDs")

        // Verify project-scoped Claude MCP server was linked onto repoA's profile
        let foundRepoA = discovered.first {
            URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == repoA.resolvingSymlinksInPath().path
        }
        XCTAssertEqual(foundRepoA?.enabledMCPServerIds, ["stripe-sandbox"])

        // Verify workspace folders carrying macOS UF_HIDDEN flag are discovered while dot-folders are skipped
        var hiddenFlagRepo = PathConstants.defaultProjectsDirectory.appendingPathComponent("uf-hidden-repo", isDirectory: true)
        let dotFolder = PathConstants.defaultProjectsDirectory.appendingPathComponent(".internal-cache", isDirectory: true)
        try fm.createDirectory(at: hiddenFlagRepo, withIntermediateDirectories: true)
        try fm.createDirectory(at: dotFolder, withIntermediateDirectories: true)
        var resValues = URLResourceValues()
        resValues.isHidden = true
        try hiddenFlagRepo.setResourceValues(resValues)

        let scannedRoot = scanner.discoverProjects(in: PathConstants.defaultProjectsDirectory)
        let scannedNames = Set(scannedRoot.map(\.name))
        XCTAssertTrue(scannedNames.contains("uf-hidden-repo"), "Folders with macOS UF_HIDDEN flag must still be discovered")
        XCTAssertFalse(scannedNames.contains(".internal-cache"), "Dot-prefixed directories must be skipped")
    }

    // MARK: - 4. First-Run Vault Bootstrap for Claude-Code-Only Users

    func testVaultBootstrapIngestsClaudeCodeOnlyUserSetup() async throws {
        // Seed ~/.claude/skills/code-audit/SKILL.md
        let claudeSkillDir = PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent("code-audit", isDirectory: true)
        try fm.createDirectory(at: claudeSkillDir, withIntermediateDirectories: true)
        let skillMD = """
        ---
        name: Code Audit
        description: Audits pull requests for regressions
        ---
        # Code Audit
        """
        try skillMD.write(to: claudeSkillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Seed ~/.claude.json with user-scoped stdio + remote HTTP MCPs and a project-scoped MCP
        let repoDir = sandboxDir.appendingPathComponent("Projects/api-service", isDirectory: true)
        try fm.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let claudeJSON: [String: Any] = [
            "mcpServers": [
                "github": [
                    "type": "stdio",
                    "command": "npx",
                    "args": ["-y", "@modelcontextprotocol/server-github"]
                ],
                "linear-remote": [
                    "type": "http",
                    "url": "https://mcp.linear.app/sse"
                ]
            ],
            "projects": [
                repoDir.path: [
                    "mcpServers": [
                        "postgres-local": [
                            "type": "stdio",
                            "command": "npx",
                            "args": ["-y", "@modelcontextprotocol/server-postgres"]
                        ]
                    ]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: claudeJSON, options: [.prettyPrinted])
            .write(to: PathConstants.claudeConfigFile)

        ProjectFolderAccessManager.shared.saveAuthorization(url: PathConstants.defaultProjectsDirectory)

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()

        let servers = await vault.loadServers()
        let serverMap = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
        XCTAssertNotNil(serverMap["github"])
        XCTAssertEqual(serverMap["linear-remote"]?.serverUrl, "https://mcp.linear.app/sse", "Claude 'url' must normalize to Vault 'serverUrl'")
        XCTAssertNotNil(serverMap["postgres-local"], "Project-scoped Claude MCP must be ingested into Master Vault")

        let globalSelection = await vault.loadGlobalSelection()
        XCTAssertTrue(globalSelection.enabledMCPServerIds.contains("github"))
        XCTAssertTrue(globalSelection.enabledMCPServerIds.contains("linear-remote"))
        XCTAssertFalse(globalSelection.enabledMCPServerIds.contains("postgres-local"), "Project-scoped MCP must not be enabled globally")
        XCTAssertTrue(globalSelection.enabledSkillIds.contains("code-audit"))

        let copiedSkillMD = PathConstants.vaultSkillsDirectory.appendingPathComponent("code-audit/SKILL.md")
        XCTAssertTrue(fm.fileExists(atPath: copiedSkillMD.path), "Claude global skill must be copied into Master Vault on first bootstrap")
    }

    // MARK: - 5. Config Backup Snapshots (Automatic Pre-Sync, Manual & Retention)

    func testConfigBackupSnapshotsAutomaticManualAndRetentionPruning() async throws {
        try fm.createDirectory(at: PathConstants.globalConfigDirectory, withIntermediateDirectories: true)
        try #"{"mcpServers":{"legacy":{"command":"node"}}}"#
            .write(to: PathConstants.globalMCPConfigFile, atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"claude-legacy":{"command":"npx"}}}"#
            .write(to: PathConstants.claudeConfigFile, atomically: true, encoding: .utf8)

        let syncEngine = SyncEngine()
        let server = MCPServerDefinition(id: "github", name: "GitHub", category: "Git", config: ["command": .string("npx")])

        // 1. First sync creates automatic pre-first-sync snapshot
        try await syncEngine.syncGlobalConfig(servers: [server], enabledIds: ["github"])
        let firstSnapshots = try fm.contentsOfDirectory(at: PathConstants.vaultBackupsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
        XCTAssertEqual(firstSnapshots.count, 1)

        let firstSnapshot = firstSnapshots[0]
        XCTAssertTrue(fm.fileExists(atPath: firstSnapshot.appendingPathComponent("mcp_config.json").path))
        XCTAssertTrue(fm.fileExists(atPath: firstSnapshot.appendingPathComponent("claude.json").path))
        let manifestData = try Data(contentsOf: firstSnapshot.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifest["trigger"] as? String, "pre-first-sync")

        // Verify backed-up file preserved pre-sync content
        let backedUpMCP = try String(contentsOf: firstSnapshot.appendingPathComponent("mcp_config.json"), encoding: .utf8)
        XCTAssertTrue(backedUpMCP.contains("legacy"))

        // 2. Subsequent non-forced sync does not create duplicate automatic snapshots
        try await syncEngine.syncGlobalConfig(servers: [server], enabledIds: [])
        let afterSecondSync = try fm.contentsOfDirectory(at: PathConstants.vaultBackupsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
        XCTAssertEqual(afterSecondSync.count, 1)

        // 3. Manual backup via AppState creates a forced snapshot including Vault JSON files
        let state = AppState(autoload: false)
        await state.vaultService.initializeVaultIfNeeded()
        let manualURL = await state.createManualConfigBackup()
        XCTAssertNotNil(manualURL)
        if let manualURL {
            let manualMeta = try JSONSerialization.jsonObject(
                with: Data(contentsOf: manualURL.appendingPathComponent("manifest.json"))
            ) as? [String: Any]
            XCTAssertEqual(manualMeta?["trigger"] as? String, "manual")
        }

        // 4. Retention pruning caps total snapshots at 10, preserves pre-first-sync, and never deletes newest snapshot
        var lastSnapshotURL: URL?
        for _ in 0..<15 {
            lastSnapshotURL = await syncEngine.createConfigSnapshotIfNeeded(force: true)
        }
        let retained = try fm.contentsOfDirectory(at: PathConstants.vaultBackupsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
        XCTAssertEqual(retained.count, 10, "Snapshot retention must prune older backups and keep 10 total snapshots")
        XCTAssertTrue(
            fm.fileExists(atPath: firstSnapshot.path),
            "Initial pre-first-sync backup must never be evicted by subsequent manual backups"
        )
        if let lastSnapshotURL {
            XCTAssertTrue(
                fm.fileExists(atPath: lastSnapshotURL.path),
                "Most recently created snapshot must never be evicted due to lexicographic suffix sorting"
            )
        }
        state.cancelPendingTasks()
    }

    // MARK: - 6. Non-.gemini Sandbox Isolation & First-Run Onboarding Server Ingestion

    func testEffectiveHomeIsolationAndOnboardingServerIngestion() async throws {
        // 1. Custom directory not named ".gemini" (e.g. ~/.gemini-sandbox) must NOT touch parent ~/.claude.json
        let fakeHome = sandboxDir.appendingPathComponent("user-home", isDirectory: true)
        let customSandbox = fakeHome.appendingPathComponent(".gemini-sandbox", isDirectory: true)
        try fm.createDirectory(at: customSandbox, withIntermediateDirectories: true)

        PathConstants.customGeminiDirectory = customSandbox
        XCTAssertEqual(
            PathConstants.claudeConfigFile.resolvingSymlinksInPath().path,
            customSandbox.appendingPathComponent(".claude.json").resolvingSymlinksInPath().path,
            "Non-.gemini custom vault path must isolate .claude.json inside itself rather than clobbering parent home"
        )

        // Restore standard test .gemini directory for onboarding flow check
        let geminiDir = sandboxDir.appendingPathComponent(".gemini", isDirectory: true)
        PathConstants.customGeminiDirectory = geminiDir

        // 2. Brand-new user authorizes workspace folder on Onboarding -> project MCP definitions must enter Master Vault
        let onboardingWorkspace = sandboxDir.appendingPathComponent("OnboardingRepos", isDirectory: true)
        let appRepo = onboardingWorkspace.appendingPathComponent("billing-api", isDirectory: true)
        let pluginDir = appRepo.appendingPathComponent(".agents/plugins/custom-billing", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try #"{"mcpServers":{"stripe-scoped":{"command":"npx","args":["-y","@stripe/mcp"]}}}"#
            .write(to: pluginDir.appendingPathComponent("mcp_config.json"), atomically: true, encoding: .utf8)

        let state = AppState(autoload: false)
        state.isProjectsFolderAuthorized = false
        await state.applyAuthorizedDirectory(url: onboardingWorkspace, updateAuthorizationState: false)

        XCTAssertTrue(
            state.servers.contains(where: { $0.id == "stripe-scoped" }),
            "applyAuthorizedDirectory on first run must ingest project-scoped MCP definitions into state.servers"
        )
        let persistedServers = await state.vaultService.loadServers()
        XCTAssertTrue(
            persistedServers.contains(where: { $0.id == "stripe-scoped" }),
            "Project-scoped MCP definitions discovered during onboarding must be saved to master_mcp.json"
        )
        state.cancelPendingTasks()
    }

    // MARK: - 7. CLI install-app, --version & Repo/Docs/Formula Hygiene Regression Guard

    func testCLIInstallAppVersionAndSourceHygieneGuard() async throws {
        // 1. --version
        let versionRes = await CLIRunner.execute(arguments: ["agymg", "--version"])
        XCTAssertEqual(versionRes.exitCode, 0)
        XCTAssertTrue(versionRes.stdout.hasPrefix("agymg "))

        // 2. install-app with dummy .app bundle
        let sourceApp = sandboxDir.appendingPathComponent("build-output/agymg.app", isDirectory: true)
        let macOSDir = sourceApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        let dummyBin = macOSDir.appendingPathComponent("agymg")
        try "#!/bin/sh\necho ok\n".write(to: dummyBin, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dummyBin.path)

        let destAppsDir = sandboxDir.appendingPathComponent("UserApplications", isDirectory: true)
        let installRes = await CLIRunner.execute(
            arguments: ["agymg", "install-app", "--source", sourceApp.path, "--dest", destAppsDir.path]
        )
        XCTAssertEqual(installRes.exitCode, 0)
        let installedBin = destAppsDir.appendingPathComponent("agymg.app/Contents/MacOS/agymg")
        XCTAssertTrue(fm.fileExists(atPath: installedBin.path))

        // Idempotent when source == dest
        let sameRes = await CLIRunner.execute(
            arguments: [
                "agymg", "install-app",
                "--source", destAppsDir.appendingPathComponent("agymg.app").path,
                "--dest", destAppsDir.path
            ]
        )
        XCTAssertEqual(sameRes.exitCode, 0)

        // Missing explicit --source bundle error path
        let missingRes = await CLIRunner.execute(
            arguments: [
                "agymg", "install-app",
                "--source", sandboxDir.appendingPathComponent("missing.app").path,
                "--dest", destAppsDir.path
            ],
            currentDirectoryPath: sandboxDir.path
        )
        XCTAssertNotEqual(missingRes.exitCode, 0, "Explicit non-existent --source must fail rather than silently installing another bundle")
        XCTAssertFalse(missingRes.stderr.isEmpty)

        let helpRes = await CLIRunner.execute(arguments: ["agymg", "--help"])
        XCTAssertEqual(helpRes.exitCode, 0)
        XCTAssertTrue(helpRes.stdout.contains("install-app"))
    }

    func testSourceHygieneZeroDiacriticsOrPersonalPaths() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scalarValues: [UInt32] = [0x010D, 0x0107, 0x017E, 0x0161, 0x0111, 0x010C, 0x0106, 0x017D, 0x0160, 0x0110]
        var forbiddenChars = CharacterSet()
        for v in scalarValues {
            if let scalar = UnicodeScalar(v) {
                forbiddenChars.insert(scalar)
            }
        }
        let personalHomePrefix = "/" + ["Users", "nikolastanojevic"].joined(separator: "/")
        let allowedExtensions: Set<String> = ["swift", "sh", "rb", "yml", "yaml", "md"]

        for folder in ["Sources", "Tests", "Scripts", "Formula", ".github"] {
            let rootURL = repoRoot.appendingPathComponent(folder, isDirectory: true)
            guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
                continue
            }
            while let fileURL = enumerator.nextObject() as? URL {
                guard allowedExtensions.contains(fileURL.pathExtension) else { continue }
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                XCTAssertNil(
                    text.rangeOfCharacter(from: forbiddenChars),
                    "Found non-English diacritic in \(fileURL.path)"
                )
                XCTAssertFalse(
                    text.contains(personalHomePrefix),
                    "Found hardcoded personal home path in \(fileURL.path)"
                )
            }
        }

        for docFile in ["README.md", "AGENTS.md", "CONTRIBUTING.md"] {
            let docURL = repoRoot.appendingPathComponent(docFile)
            let text = try String(contentsOf: docURL, encoding: .utf8)
            XCTAssertNil(text.rangeOfCharacter(from: forbiddenChars), "Found non-English diacritic in \(docFile)")
            XCTAssertFalse(text.contains(personalHomePrefix), "Found hardcoded personal home path in \(docFile)")
        }

        // Verify Homebrew formula desc <= 80 chars and package_app.sh uses --disable-sandbox
        let formulaText = try String(contentsOf: repoRoot.appendingPathComponent("Formula/agymg.rb"), encoding: .utf8)
        let descLine = try XCTUnwrap(formulaText.components(separatedBy: .newlines).first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("desc \"") })
        let descParts = descLine.split(separator: "\"")
        XCTAssertGreaterThanOrEqual(descParts.count, 2)
        XCTAssertLessThanOrEqual(descParts[1].count, 80, "Homebrew formula desc must be <= 80 characters")

        let packageScript = try String(contentsOf: repoRoot.appendingPathComponent("Scripts/package_app.sh"), encoding: .utf8)
        XCTAssertTrue(
            packageScript.contains("--disable-sandbox"),
            "package_app.sh must pass --disable-sandbox to swift build so Homebrew sandbox builds succeed"
        )

        // Verify every `agymg <subcommand>` example in README.md is a real supported CLI subcommand
        let readmeText = try String(contentsOf: repoRoot.appendingPathComponent("README.md"), encoding: .utf8)
        for rawLine in readmeText.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("agymg ") {
                let tokens = trimmed.split(separator: " ").map(String.init)
                if tokens.count >= 2 {
                    XCTAssertTrue(
                        CLIRunner.supportedSubcommands.contains(tokens[1]),
                        "README CLI example '\(trimmed)' uses unsupported subcommand '\(tokens[1])'"
                    )
                }
            }
        }
    }
}
