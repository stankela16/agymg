import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

@MainActor
final class Phases2To4ImprovementsTests: XCTestCase {
    private var sandboxDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("Phases2To4Tests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        sandboxDir = dir

        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.saveAuthorization(url: projectsDir)

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let sandboxDir {
            try? fm.removeItem(at: sandboxDir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Phase 0b: Rebranded Assets

    func testRebrandedAssetsResolveAndMenuBarIconIs18ptTemplate() {
        XCTAssertNotNil(MenuBarIconProvider.resourceURL(forResource: "AppIcon", withExtension: "icns"))
        XCTAssertNotNil(MenuBarIconProvider.resourceURL(forResource: "AppLogo", withExtension: "png"))
        XCTAssertNotNil(MenuBarIconProvider.resourceURL(forResource: "MenuBarIconTemplate", withExtension: "png"))
        XCTAssertNotNil(MenuBarIconProvider.resourceURL(forResource: "MenuBarIconTemplate@2x", withExtension: "png"))

        let icon = MenuBarIconProvider.icon
        XCTAssertNotNil(icon)
        XCTAssertEqual(icon?.size.width ?? 0, 18.0, accuracy: 0.1)
        XCTAssertEqual(icon?.size.height ?? 0, 18.0, accuracy: 0.1)
        XCTAssertTrue(icon?.isTemplate ?? false)

        let appLogoView = AppLogoView(size: 24)
        XCTAssertNotNil(appLogoView.body)
    }

    // MARK: - Phase 2: Multi-Stack Detection & Dynamic Vault Skill Matching

    func testRecommendationServiceMultiStackCloudflareGeminiESP32PythonGoRust() throws {
        let servers = [
            MCPServerDefinition(id: "cloudflare", name: "Cloudflare", category: "Cloud", config: ["command": .string("npx")]),
            MCPServerDefinition(id: "supabase", name: "Supabase", category: "Database", config: ["command": .string("npx")])
        ]
        let plugins = [
            PluginDefinition(id: "cloudflare", name: "Cloudflare", path: "/tmp/cf"),
            PluginDefinition(id: "gemini-api", name: "Gemini API", path: "/tmp/gem"),
            PluginDefinition(id: "build-macos-apps", name: "Build macOS Apps", path: "/tmp/mac")
        ]
        let skills = [
            SkillDefinition(id: "esp32-desk-gadget", name: "ESP32 Desk Gadget", description: "Control ESP32 TFT display", path: "/tmp/esp"),
            SkillDefinition(id: "apple-onboarding-cro", name: "Apple Onboarding CRO", description: "iOS App Store onboarding optimization", path: "/tmp/ioscro"),
            SkillDefinition(id: "rust-async-guide", name: "Rust Async Guide", description: "Best practices for Rust tokio systems", path: "/tmp/rust"),
            SkillDefinition(id: "ask", name: "Ask", description: "Answer python and rust questions directly", path: "/tmp/ask"),
            SkillDefinition(id: "logo-design", name: "Logo Design", description: "Design SVG logos", path: "/tmp/logo")
        ]

        let service = ProjectRecommendationService()

        // 1. Cloudflare + Gemini API
        let cfDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("cf-worker", isDirectory: true)
        try fm.createDirectory(at: cfDir, withIntermediateDirectories: true)
        try "name = \"worker\"\n".write(to: cfDir.appendingPathComponent("wrangler.toml"), atomically: true, encoding: .utf8)
        try #"{"dependencies":{"@google/genai":"1.0.0"}}"#.write(to: cfDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let cfRecs = service.recommend(
            for: ProjectProfile(id: "cf-worker", name: "cf-worker", path: cfDir.path),
            availableServers: servers,
            globalServerIds: [],
            availableSkills: skills,
            globalSkillIds: [],
            availablePlugins: plugins,
            globalPluginIds: []
        )
        let cfKeys = Set(cfRecs.map(\.uniqueKey))
        XCTAssertTrue(cfKeys.contains("plugin:cloudflare"))
        XCTAssertTrue(cfKeys.contains("mcp:cloudflare"))
        XCTAssertTrue(cfKeys.contains("plugin:gemini-api"))

        // 2. ESP32 firmware project
        let espDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("esp32-node", isDirectory: true)
        try fm.createDirectory(at: espDir, withIntermediateDirectories: true)
        try "[env:esp32dev]\nplatform = espressif32\n".write(to: espDir.appendingPathComponent("platformio.ini"), atomically: true, encoding: .utf8)

        let espRecs = service.recommend(
            for: ProjectProfile(id: "esp32-node", name: "esp32-node", path: espDir.path),
            availableServers: servers,
            globalServerIds: [],
            availableSkills: skills,
            globalSkillIds: [],
            availablePlugins: plugins,
            globalPluginIds: []
        )
        XCTAssertTrue(espRecs.contains(where: { $0.uniqueKey == "skill:esp32-desk-gadget" }))

        // 3. Python project (pyproject.toml + requirements.txt)
        let pyDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("py-backend", isDirectory: true)
        try fm.createDirectory(at: pyDir, withIntermediateDirectories: true)
        try "[project]\nname = \"py-backend\"\n".write(to: pyDir.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)
        try "fastapi==0.115.0\nsupabase>=2.0.0\ngoogle-genai>=1.0.0\n".write(to: pyDir.appendingPathComponent("requirements.txt"), atomically: true, encoding: .utf8)

        let pyStack = service.inspectStack(at: pyDir.path)
        XCTAssertTrue(pyStack.hasPythonMarker)
        XCTAssertTrue(pyStack.hasSupabaseMarker)
        XCTAssertTrue(pyStack.hasGeminiAPIMarker)
        XCTAssertTrue(pyStack.stackLabels.contains("Python"))
        XCTAssertTrue(pyStack.stackLabels.contains("Supabase"))
        XCTAssertTrue(pyStack.stackLabels.contains("Gemini API"))

        // 4. Rust + Go project: dynamic Vault skill matching & meta-skill exclusion
        let rustDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("rust-cli", isDirectory: true)
        try fm.createDirectory(at: rustDir, withIntermediateDirectories: true)
        try "[package]\nname = \"rust-cli\"\n".write(to: rustDir.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try "module example.com/rustcli\n".write(to: rustDir.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)

        let rustStack = service.inspectStack(at: rustDir.path)
        XCTAssertTrue(rustStack.hasRustMarker)
        XCTAssertTrue(rustStack.hasGoMarker)

        let rustRecs = service.recommend(
            for: ProjectProfile(id: "rust-cli", name: "rust-cli", path: rustDir.path),
            availableServers: servers,
            globalServerIds: [],
            availableSkills: skills,
            globalSkillIds: [],
            availablePlugins: plugins,
            globalPluginIds: []
        )
        XCTAssertTrue(rustRecs.contains(where: { $0.uniqueKey == "skill:rust-async-guide" }))
        XCTAssertFalse(rustRecs.contains(where: { $0.id == "ask" }), "Meta skill 'ask' must never be dynamically recommended")
        XCTAssertFalse(rustRecs.contains(where: { $0.id == "logo-design" }), "Unrelated design skill must not be recommended")

        // 5. iOS-only Xcode project recommends apple-onboarding-cro and still excludes build-macos-apps
        let iosDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("ios-app", isDirectory: true)
        let xcDir = iosDir.appendingPathComponent("App.xcodeproj", isDirectory: true)
        try fm.createDirectory(at: xcDir, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;\n".write(to: xcDir.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

        let iosRecs = service.recommend(
            for: ProjectProfile(id: "ios-app", name: "ios-app", path: iosDir.path),
            availableServers: servers,
            globalServerIds: [],
            availableSkills: skills,
            globalSkillIds: [],
            availablePlugins: plugins,
            globalPluginIds: []
        )
        XCTAssertTrue(iosRecs.contains(where: { $0.uniqueKey == "skill:apple-onboarding-cro" }))
        XCTAssertFalse(iosRecs.contains(where: { $0.uniqueKey == "plugin:build-macos-apps" }))
    }

    // MARK: - Phase 3: MCP Diagnostics, Drift, Doctor CLI, & IDE Monitor

    func testMCPDiagnosticsOAuthSecretAirlockDriftAndDoctorCLI() async throws {
        // Seed OAuth tokens file with an expired token + refresh token and sensitive secret string
        let secretOAuthToken = "oauth_SUPER_SECRET_TOKEN_999"
        let oauthPayload: [String: Any] = [
            "https://api.example.com/mcp": [
                "token": [
                    "access_token": secretOAuthToken,
                    "refresh_token": "refresh_SECRET_111",
                    "expiry": "2020-01-01T00:00:00Z"
                ]
            ]
        ]
        try fm.createDirectory(at: PathConstants.antigravityEngineDirectory, withIntermediateDirectories: true)
        let oauthData = try JSONSerialization.data(withJSONObject: oauthPayload, options: [.prettyPrinted])
        try oauthData.write(to: PathConstants.engineMCPOAuthTokensFile)

        let placeholderSecret = "YOUR_API_KEY_HERE"
        let servers = [
            MCPServerDefinition(
                id: "valid-sh",
                name: "Valid Shell",
                category: "Tools",
                config: ["command": .string("/bin/sh")]
            ),
            MCPServerDefinition(
                id: "missing-bin",
                name: "Missing Binary",
                category: "Tools",
                config: ["command": .string("nonexistent_agymg_binary_xyz_123")]
            ),
            MCPServerDefinition(
                id: "placeholder-env",
                name: "Placeholder Env",
                category: "Tools",
                config: [
                    "command": .string("/bin/sh"),
                    "env": .object(["SERVICE_TOKEN": .string(placeholderSecret)])
                ]
            ),
            MCPServerDefinition(
                id: "remote-oauth",
                name: "Remote OAuth",
                category: "Design",
                config: ["serverUrl": .string("https://api.example.com/mcp")]
            )
        ]

        let vault = VaultService()
        await vault.saveServers(servers)
        await vault.saveGlobalSelection(GlobalSelection(enabledMCPServerIds: ["valid-sh"], enabledSkillIds: [], enabledPluginIds: []))

        let diag = MCPDiagnosticsService()
        let healthMap = diag.inspectAllServers(servers)
        XCTAssertEqual(healthMap["valid-sh"]?.state, .healthy)
        XCTAssertEqual(healthMap["missing-bin"]?.state, .error)
        XCTAssertEqual(healthMap["placeholder-env"]?.state, .warning)
        XCTAssertEqual(healthMap["remote-oauth"]?.state, .warning)
        XCTAssertFalse(healthMap["placeholder-env"]?.detail.contains(placeholderSecret) ?? true)
        XCTAssertFalse(healthMap["remote-oauth"]?.detail.contains(secretOAuthToken) ?? true)

        // Write stale ~/.gemini/config/mcp_config.json where global server 'valid-sh' is missing -> drift detected
        try fm.createDirectory(at: PathConstants.globalConfigDirectory, withIntermediateDirectories: true)
        let staleConfig = Data("{\"mcpServers\":{}}".utf8)
        try staleConfig.write(to: PathConstants.globalMCPConfigFile)

        let driftBefore = diag.detectDrift(
            servers: servers,
            globalServerIds: ["valid-sh"],
            skills: [],
            globalSkillIds: [],
            projects: []
        )
        XCTAssertTrue(driftBefore.hasDrift)

        // CLI `agymg doctor --json` reports issues and NEVER leaks OAuth token or env secrets
        let doctorRes = await CLIRunner.execute(arguments: ["agymg", "doctor", "--json"])
        XCTAssertEqual(doctorRes.exitCode, 0)
        XCTAssertFalse(doctorRes.stdout.contains(secretOAuthToken), "Doctor output must never leak OAuth access_token")
        XCTAssertFalse(doctorRes.stdout.contains("refresh_SECRET_111"), "Doctor output must never leak refresh_token")
        XCTAssertFalse(doctorRes.stdout.contains(placeholderSecret), "Doctor output must never print raw env values")

        let decodedDoctor = try JSONDecoder.withISO8601.decode(CLIDoctorResponse.self, from: Data(doctorRes.stdout.utf8))
        XCTAssertEqual(decodedDoctor.status, "error")
        XCTAssertGreaterThanOrEqual(decodedDoctor.errorCount, 1)
        XCTAssertGreaterThanOrEqual(decodedDoctor.warningCount, 3)

        // Sync global config -> drift on valid-sh & claude resolved
        let syncEngine = SyncEngine()
        try await syncEngine.syncGlobalConfig(servers: servers, enabledIds: ["valid-sh"])
        let driftAfter = diag.detectDrift(
            servers: servers,
            globalServerIds: ["valid-sh"],
            skills: [],
            globalSkillIds: [],
            projects: []
        )
        XCTAssertFalse(driftAfter.hasDrift, "After global sync, global drift issues should disappear")
    }

    func testActiveWorkspaceMonitorSupportsXcodeWindsurfAndZed() async throws {
        XCTAssertTrue(ActiveWorkspaceMonitor.isRelevantIDE(bundleId: "com.apple.dt.Xcode", appName: "Xcode"))
        XCTAssertTrue(ActiveWorkspaceMonitor.isRelevantIDE(bundleId: "com.exafunction.windsurf", appName: "Windsurf"))
        XCTAssertTrue(ActiveWorkspaceMonitor.isRelevantIDE(bundleId: "dev.zed.Zed", appName: "Zed"))

        let home = PathConstants.effectiveHomeDirectory
        let xcodeProjDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("XcodeSample", isDirectory: true)
        let xcprojBundle = xcodeProjDir.appendingPathComponent("Sample.xcodeproj", isDirectory: true)
        try fm.createDirectory(at: xcprojBundle, withIntermediateDirectories: true)

        let ddAppDir = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Sample-abc/info.plist")
        try fm.createDirectory(at: ddAppDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plistDict: [String: Any] = ["WorkspacePath": xcprojBundle.path]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try plistData.write(to: ddAppDir)

        let detectedXcode = ActiveWorkspaceMonitor.detectWorkspaceForApp(
            bundleId: "com.apple.dt.Xcode",
            appName: "Xcode",
            home: home
        )
        XCTAssertEqual(detectedXcode?.path, xcodeProjDir.path)
        XCTAssertEqual(detectedXcode?.source, "xcode")

        // Windsurf storage.json detection
        let windsurfProj = PathConstants.desktopProjectsDirectory.appendingPathComponent("WindsurfSample", isDirectory: true)
        try fm.createDirectory(at: windsurfProj, withIntermediateDirectories: true)
        let wsStorage = home.appendingPathComponent("Library/Application Support/Windsurf/User/globalStorage/storage.json")
        try fm.createDirectory(at: wsStorage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"windowsState":{"lastActiveWindow":{"folder":"file://\#(windsurfProj.path)"}}}"#
            .write(to: wsStorage, atomically: true, encoding: .utf8)

        let detectedWS = ActiveWorkspaceMonitor.detectWorkspaceForApp(
            bundleId: "com.exafunction.windsurf",
            appName: "Windsurf",
            home: home
        )
        XCTAssertEqual(detectedWS?.path, windsurfProj.path)
    }

    // MARK: - Phase 4: Skill Import, Copy Setup & MenuBar Search/Quick Actions

    func testSkillImportServiceLocalNestedRepoParseGitHubURLAndCLISubcommand() async throws {
        // 1. GitHub URL parser validation
        let parsed = try SkillImportService.parseGitHubURL("https://github.com/acme/agent-skills/tree/main/skills/custom-skill/")
        XCTAssertEqual(parsed.repoCloneURL, "https://github.com/acme/agent-skills.git")
        XCTAssertEqual(parsed.branch, "main")
        XCTAssertEqual(parsed.subpath, "skills/custom-skill")
        XCTAssertEqual(parsed.suggestedSkillId, "custom-skill")

        XCTAssertThrowsError(try SkillImportService.parseGitHubURL("http://github.com/acme/repo"))
        XCTAssertThrowsError(try SkillImportService.parseGitHubURL("https://evil.com/acme/repo"))

        // 2. Import nested skills/<id>/SKILL.md folder via CLI
        let sourceRepo = sandboxDir.appendingPathComponent("external-skill-repo", isDirectory: true)
        let nestedSkill = sourceRepo.appendingPathComponent("skills/nested-helper", isDirectory: true)
        try fm.createDirectory(at: nestedSkill, withIntermediateDirectories: true)
        try """
        ---
        name: Nested Helper
        description: Helpful imported skill
        ---

        # Nested Helper
        """
        .write(to: nestedSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let cliImport = await CLIRunner.execute(
            arguments: ["agymg", "import-skill", sourceRepo.path, "--json"]
        )
        XCTAssertEqual(cliImport.exitCode, 0)
        XCTAssertTrue(cliImport.stderr.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: PathConstants.vaultSkillsDirectory.appendingPathComponent("nested-helper/SKILL.md").path))

        let decodedSkill = try JSONDecoder().decode(SkillDefinition.self, from: Data(cliImport.stdout.utf8))
        XCTAssertEqual(decodedSkill.id, "nested-helper")
        XCTAssertEqual(decodedSkill.name, "Nested Helper")

        // Duplicate import without --overwrite must fail cleanly
        let duplicateAttempt = await CLIRunner.execute(
            arguments: ["agymg", "import-skill", sourceRepo.path]
        )
        XCTAssertNotEqual(duplicateAttempt.exitCode, 0)

        // Overwrite import via --overwrite succeeds
        let overwriteAttempt = await CLIRunner.execute(
            arguments: ["agymg", "import-skill", sourceRepo.path, "--overwrite", "--json"]
        )
        XCTAssertEqual(overwriteAttempt.exitCode, 0)
    }

    func testCopyProjectSetupMergeAndReplaceAndMenuBarFittingSize() async throws {
        let projA = PathConstants.desktopProjectsDirectory.appendingPathComponent("source-proj", isDirectory: true)
        let projB = PathConstants.desktopProjectsDirectory.appendingPathComponent("target-proj", isDirectory: true)
        try fm.createDirectory(at: projA, withIntermediateDirectories: true)
        try fm.createDirectory(at: projB, withIntermediateDirectories: true)

        let state = AppState(autoload: false)
        state.servers = [
            MCPServerDefinition(id: "mcp-1", name: "MCP 1", category: "Tools", config: ["command": .string("/bin/sh")]),
            MCPServerDefinition(id: "mcp-2", name: "MCP 2", category: "Tools", config: ["command": .string("/bin/sh")]),
            MCPServerDefinition(id: "mcp-3", name: "MCP 3", category: "Tools", config: ["command": .string("/bin/sh")])
        ]
        state.skills = [
            SkillDefinition(id: "sk-1", name: "Skill 1", description: "One", path: "/tmp/sk1"),
            SkillDefinition(id: "sk-2", name: "Skill 2", description: "Two", path: "/tmp/sk2")
        ]
        state.plugins = [
            PluginDefinition(id: "pl-1", name: "Plugin 1", path: "/tmp/pl1")
        ]
        state.projects = [
            ProjectProfile(
                id: "source-proj",
                name: "source-proj",
                path: projA.path,
                enabledMCPServerIds: ["mcp-1", "mcp-2"],
                enabledSkillIds: ["sk-1"],
                enabledPluginIds: ["pl-1"]
            ),
            ProjectProfile(
                id: "target-proj",
                name: "target-proj",
                path: projB.path,
                enabledMCPServerIds: ["mcp-3"],
                enabledSkillIds: ["sk-2"],
                enabledPluginIds: []
            )
        ]

        // 1. Merge preserves target's existing mcp-3 / sk-2 while adding source's tools
        state.copySetup(from: "source-proj", to: "target-proj", mode: .merge)
        let mergedTarget = try XCTUnwrap(state.projects.first(where: { $0.id == "target-proj" }))
        XCTAssertEqual(mergedTarget.enabledMCPServerIds, ["mcp-1", "mcp-2", "mcp-3"])
        XCTAssertEqual(mergedTarget.enabledSkillIds, ["sk-1", "sk-2"])
        XCTAssertEqual(mergedTarget.enabledPluginIds, ["pl-1"])

        // 2. Replace overwrites target setup to match source exactly
        state.copySetup(from: "source-proj", to: "target-proj", mode: .replace)
        let replacedTarget = try XCTUnwrap(state.projects.first(where: { $0.id == "target-proj" }))
        XCTAssertEqual(replacedTarget.enabledMCPServerIds, ["mcp-1", "mcp-2"])
        XCTAssertEqual(replacedTarget.enabledSkillIds, ["sk-1"])
        XCTAssertEqual(replacedTarget.enabledPluginIds, ["pl-1"])

        // 3. MenuBarPopoverView keeps required 360pt width & >= 420pt fitting height with source badge + quick actions + search
        state.selectedProjectId = "target-proj"
        state.activeWorkspaceSource = "xcode"
        let popover = MenuBarPopoverView(state: state)
        let hostingView = NSHostingView(rootView: popover)
        let size = hostingView.fittingSize
        XCTAssertEqual(size.width, DesignTokens.Dimensions.popoverWidth, accuracy: 2.0)
        XCTAssertGreaterThanOrEqual(size.height, 420.0)

        state.cancelPendingTasks()
    }
}

private extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
