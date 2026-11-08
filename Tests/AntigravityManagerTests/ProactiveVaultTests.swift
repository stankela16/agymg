import XCTest
import SwiftUI
@testable import AntigravityManager

@MainActor
final class ProactiveVaultTests: XCTestCase {
    private var sandboxDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("ProactiveVaultTests_\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Helpers
    private func seedVaultCatalog() async throws {
        let vault = VaultService()
        let servers: [MCPServerDefinition] = [
            MCPServerDefinition(
                id: "github",
                name: "GitHub",
                category: "Git",
                config: [
                    "command": .string("npx"),
                    "env": .object(["GITHUB_PERSONAL_ACCESS_TOKEN": .string("ghp_SUPER_SECRET_TOKEN_111")])
                ]
            ),
            MCPServerDefinition(
                id: "supabase",
                name: "Supabase",
                category: "Database",
                config: [
                    "command": .string("npx"),
                    "env": .object(["SUPABASE_ACCESS_TOKEN": .string("sbp_SUPER_SECRET_TOKEN_222")])
                ]
            ),
            MCPServerDefinition(
                id: "posthog",
                name: "PostHog",
                category: "Analytics",
                config: [
                    "serverUrl": .string("https://mcp.posthog.com/sse?key=phx_SUPER_SECRET_333"),
                    "headers": .object(["Authorization": .string("Bearer phx_SUPER_SECRET_333")])
                ]
            ),
            MCPServerDefinition(
                id: "polar",
                name: "Polar",
                category: "Payments",
                config: [
                    "command": .string("npx"),
                    "env": .object(["POLAR_ACCESS_TOKEN": .string("polar_pat_SUPER_SECRET_444")])
                ]
            ),
            MCPServerDefinition(
                id: "shadcn",
                name: "Shadcn",
                category: "Web",
                config: ["command": .string("npx")]
            ),
            MCPServerDefinition(
                id: "vercel",
                name: "Vercel",
                category: "Cloud",
                config: ["command": .string("npx")]
            ),
            MCPServerDefinition(
                id: "telegram",
                name: "Telegram",
                category: "Communication",
                config: ["command": .string("npx")]
            )
        ]
        await vault.saveServers(servers)

        // Seed skills in Vault
        let skillSpecs: [(id: String, name: String, desc: String)] = [
            ("ask", "Ask", "Direct Q&A skill"),
            ("vault", "Vault", "Proactive Vault radar and control skill"),
            ("macos-ui-design-pro", "macOS UI Design Pro", "Apple HIG & SwiftUI design system"),
            ("macos-spm-app-packaging", "macOS SPM App Packaging", "Package SwiftPM apps"),
            ("ui-architect", "UI Architect", "Frontend UI architecture"),
            ("vercel-web-design-guidelines", "Vercel Web Design Guidelines", "Web UI standards"),
            ("telegram-bot-builder", "Telegram Bot Builder", "Telegram bot patterns"),
            ("hetzner-vps-ops", "Hetzner VPS Ops", "Docker and VPS deployment"),
            ("security-review", "Security Review", "Auth and database security audit"),
            ("remotion-studio", "Remotion Studio", "Video creation with Remotion")
        ]

        for spec in skillSpecs {
            let dir = PathConstants.vaultSkillsDirectory.appendingPathComponent(spec.id, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let md = """
            ---
            name: \(spec.name)
            description: \(spec.desc)
            ---
            # \(spec.name)
            """
            try md.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }

        // Seed plugins in Vault
        let pluginSpecs: [(id: String, name: String, desc: String)] = [
            ("build-macos-apps", "Build macOS Apps", "SwiftUI and AppKit engineering plugin"),
            ("modern-web-guidance-plugin", "Modern Web Guidance", "Modern frontend engineering plugin"),
            ("chrome-devtools-plugin", "Chrome DevTools", "Browser debugging plugin")
        ]
        for p in pluginSpecs {
            let dir = PathConstants.vaultPluginsDirectory.appendingPathComponent(p.id, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let pJson = try JSONSerialization.data(withJSONObject: ["name": p.name, "description": p.desc])
            try pJson.write(to: dir.appendingPathComponent("plugin.json"))
        }

        await vault.saveGlobalSelection(GlobalSelection(
            enabledMCPServerIds: ["github"],
            enabledSkillIds: ["ask", "vault"],
            enabledPluginIds: []
        ))
    }

    // MARK: - 1. ProjectRecommendationService Stack Detection & Filtering Tests
    func testRecommendationServiceSwiftMacOSProject() async throws {
        try await seedVaultCatalog()
        let vault = VaultService()
        let servers = await vault.loadServers()
        let skills = SkillScannerService().scanVaultSkills()
        let plugins = PluginScannerService().scanVaultPlugins()
        let globalSel = await vault.loadGlobalSelection()

        let macProjDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("mac-utility", isDirectory: true)
        try fm.createDirectory(at: macProjDir, withIntermediateDirectories: true)
        let pkgSwift = """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "mac-utility", platforms: [.macOS(.v14)])
        """
        try pkgSwift.write(to: macProjDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        var profile = ProjectProfile(id: "mac-utility", name: "mac-utility", path: macProjDir.path)
        let service = ProjectRecommendationService()

        let recs = service.recommend(
            for: profile,
            availableServers: servers,
            globalServerIds: globalSel.enabledMCPServerIds,
            availableSkills: skills,
            globalSkillIds: globalSel.enabledSkillIds,
            availablePlugins: plugins,
            globalPluginIds: globalSel.enabledPluginIds
        )

        let recIds = Set(recs.map(\.uniqueKey))
        XCTAssertTrue(recIds.contains("plugin:build-macos-apps"), "Should recommend build-macos-apps plugin for Swift macOS package")
        XCTAssertTrue(recIds.contains("skill:macos-ui-design-pro"), "Should recommend macos-ui-design-pro skill")
        XCTAssertTrue(recIds.contains("skill:macos-spm-app-packaging"), "Should recommend macos-spm-app-packaging skill")
        XCTAssertFalse(recIds.contains("mcp:supabase"), "Should NOT recommend unrelated web/database MCPs")

        // Once enabled on the project, they must no longer be recommended
        profile.enabledPluginIds.insert("build-macos-apps")
        profile.enabledSkillIds.insert("macos-ui-design-pro")

        let updatedRecs = service.recommend(
            for: profile,
            availableServers: servers,
            globalServerIds: globalSel.enabledMCPServerIds,
            availableSkills: skills,
            globalSkillIds: globalSel.enabledSkillIds,
            availablePlugins: plugins,
            globalPluginIds: globalSel.enabledPluginIds
        )
        let updatedIds = Set(updatedRecs.map(\.uniqueKey))
        XCTAssertFalse(updatedIds.contains("plugin:build-macos-apps"))
        XCTAssertFalse(updatedIds.contains("skill:macos-ui-design-pro"))
        XCTAssertTrue(updatedIds.contains("skill:macos-spm-app-packaging"))
    }

    func testRecommendationServiceWebSaaSProject() async throws {
        try await seedVaultCatalog()
        let vault = VaultService()
        let servers = await vault.loadServers()
        let skills = SkillScannerService().scanVaultSkills()
        let plugins = PluginScannerService().scanVaultPlugins()
        let globalSel = await vault.loadGlobalSelection()

        let webProjDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("saas-web", isDirectory: true)
        try fm.createDirectory(at: webProjDir, withIntermediateDirectories: true)

        let packageJSON: [String: Any] = [
            "name": "saas-web",
            "dependencies": [
                "next": "15.0.0",
                "react": "19.0.0",
                "@supabase/supabase-js": "2.45.0",
                "posthog-js": "1.160.0",
                "@polar-sh/sdk": "0.10.0"
            ],
            "devDependencies": [
                "tailwindcss": "3.4.0"
            ]
        ]
        let pkgData = try JSONSerialization.data(withJSONObject: packageJSON, options: [.prettyPrinted])
        try pkgData.write(to: webProjDir.appendingPathComponent("package.json"))
        try "{}".write(to: webProjDir.appendingPathComponent("components.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: webProjDir.appendingPathComponent("vercel.json"), atomically: true, encoding: .utf8)

        let profile = ProjectProfile(id: "saas-web", name: "saas-web", path: webProjDir.path)
        let service = ProjectRecommendationService()
        let recs = service.recommend(
            for: profile,
            availableServers: servers,
            globalServerIds: globalSel.enabledMCPServerIds,
            availableSkills: skills,
            globalSkillIds: globalSel.enabledSkillIds,
            availablePlugins: plugins,
            globalPluginIds: globalSel.enabledPluginIds
        )

        let recKeys = Set(recs.map(\.uniqueKey))
        XCTAssertTrue(recKeys.contains("mcp:supabase"))
        XCTAssertTrue(recKeys.contains("mcp:posthog"))
        XCTAssertTrue(recKeys.contains("mcp:polar"))
        XCTAssertTrue(recKeys.contains("mcp:shadcn"))
        XCTAssertTrue(recKeys.contains("mcp:vercel"))
        XCTAssertTrue(recKeys.contains("plugin:modern-web-guidance-plugin"))
        XCTAssertTrue(recKeys.contains("skill:ui-architect"))
        XCTAssertTrue(recKeys.contains("skill:security-review"))
        // github is already global, so it must NOT be in recommendations
        XCTAssertFalse(recKeys.contains("mcp:github"))
    }

    // MARK: - 2. CLIRunner Brief, Set & Secret Protection Tests
    func testCLIRunnerBriefAndSecretAirlockProtection() async throws {
        try await seedVaultCatalog()
        let projDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("secret-check-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        let pkgJSON = #"{"dependencies":{"@supabase/supabase-js":"2.0.0","posthog-js":"1.0.0"}}"#
        try pkgJSON.write(to: projDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let vault = VaultService()
        let profile = ProjectProfile(
            id: "secret-check-proj",
            name: "secret-check-proj",
            path: projDir.path,
            enabledMCPServerIds: ["posthog"],
            enabledSkillIds: ["ui-architect"],
            enabledPluginIds: []
        )
        await vault.saveProjects([profile])

        // 1. Test JSON brief output
        let briefResult = await CLIRunner.execute(
            arguments: ["agymg", "brief", "--project", projDir.path, "--json"]
        )
        XCTAssertEqual(briefResult.exitCode, 0)
        XCTAssertTrue(briefResult.stderr.isEmpty)

        // Verify NO secret tokens from master_mcp.json leak into stdout!
        let forbiddenSecrets = [
            "ghp_SUPER_SECRET_TOKEN_111",
            "sbp_SUPER_SECRET_TOKEN_222",
            "phx_SUPER_SECRET_333",
            "polar_pat_SUPER_SECRET_444"
        ]
        for secret in forbiddenSecrets {
            XCTAssertFalse(
                briefResult.stdout.contains(secret),
                "CRITICAL SECURITY VIOLATION: Secret '\(secret)' leaked in 'agymg brief --json' stdout!"
            )
        }

        // Decode CLIBriefResponse
        let data = Data(briefResult.stdout.utf8)
        let decoded = try JSONDecoder().decode(CLIBriefResponse.self, from: data)
        XCTAssertEqual(decoded.project.id, "secret-check-proj")
        XCTAssertTrue(decoded.active.projectMCPs.contains(where: { $0.id == "posthog" }))
        XCTAssertTrue(decoded.active.globalMCPs.contains(where: { $0.id == "github" }))
        XCTAssertTrue(decoded.active.projectSkills.contains(where: { $0.id == "ui-architect" }))
        // supabase is in package.json and not yet enabled, so it must be recommended
        XCTAssertTrue(decoded.recommendations.contains(where: { $0.id == "supabase" && $0.kind == .mcp }))
        // posthog is already enabled, so it must NOT be recommended
        XCTAssertFalse(decoded.recommendations.contains(where: { $0.id == "posthog" }))

        // 2. Test Markdown brief output
        let mdResult = await CLIRunner.execute(
            arguments: ["agymg", "brief", "--project", projDir.path]
        )
        XCTAssertEqual(mdResult.exitCode, 0)
        XCTAssertTrue(mdResult.stdout.contains("Vault Brief: secret-check-proj"))
        for secret in forbiddenSecrets {
            XCTAssertFalse(mdResult.stdout.contains(secret), "Secret '\(secret)' must never leak in markdown brief")
        }
    }

    func testCLIRunnerSetEnablesAndDisablesProjectAndGlobalResources() async throws {
        try await seedVaultCatalog()
        let projDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("cli-set-proj", isDirectory: true)
        let subDir = projDir.appendingPathComponent("src/components", isDirectory: true)
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)

        let vault = VaultService()
        let initialProfile = ProjectProfile(id: "cli-set-proj", name: "cli-set-proj", path: projDir.path)
        await vault.saveProjects([initialProfile])

        // 1. Run `agymg set` targeting a subdirectory of the project
        let setRes = await CLIRunner.execute(
            arguments: [
                "agymg", "set",
                "--project", subDir.path,
                "--enable-mcp", "supabase,polar",
                "--enable-skill", "ui-architect",
                "--enable-plugin", "modern-web-guidance-plugin",
                "--json"
            ]
        )
        XCTAssertEqual(setRes.exitCode, 0)
        let decodedSet = try JSONDecoder().decode(CLISetResponse.self, from: Data(setRes.stdout.utf8))
        XCTAssertEqual(decodedSet.targetId, "cli-set-proj")
        XCTAssertEqual(Set(decodedSet.enabledMCPs), Set(["supabase", "polar"]))
        XCTAssertEqual(decodedSet.enabledSkills, ["ui-architect"])
        XCTAssertEqual(decodedSet.enabledPlugins, ["modern-web-guidance-plugin"])
        XCTAssertTrue(decodedSet.requiresSessionReloadForMCP)

        // Verify disk sync artifacts were created
        let mcpManifest = projDir.appendingPathComponent(".agents/plugins/agy-manager/mcp_config.json")
        XCTAssertTrue(fm.fileExists(atPath: mcpManifest.path), "SyncEngine must write .agents/plugins/agy-manager/mcp_config.json")
        let skillSymlink = projDir.appendingPathComponent(".agents/skills/ui-architect")
        XCTAssertTrue(fm.fileExists(atPath: skillSymlink.path), "SyncEngine must symlink enabled skill into .agents/skills")
        let claudeSkillSymlink = projDir.appendingPathComponent(".claude/skills/ui-architect")
        XCTAssertTrue(fm.fileExists(atPath: claudeSkillSymlink.path), "SyncEngine must symlink enabled skill into .claude/skills")

        // 2. Disable polar MCP and test skill-only change (requiresSessionReloadForMCP == false)
        let disableSkillRes = await CLIRunner.execute(
            arguments: [
                "agymg", "set",
                "--project", projDir.path,
                "--disable-skill", "ui-architect",
                "--enable-skill", "security-review",
                "--json"
            ]
        )
        XCTAssertEqual(disableSkillRes.exitCode, 0)
        let decodedSkillOnly = try JSONDecoder().decode(CLISetResponse.self, from: Data(disableSkillRes.stdout.utf8))
        XCTAssertFalse(decodedSkillOnly.requiresSessionReloadForMCP, "Skill-only change should not require MCP session reload")
        XCTAssertFalse(fm.fileExists(atPath: skillSymlink.path))
        XCTAssertTrue(fm.fileExists(atPath: projDir.appendingPathComponent(".agents/skills/security-review").path))

        // 3. Test Global set
        let globalRes = await CLIRunner.execute(
            arguments: [
                "agymg", "set",
                "--global",
                "--enable-mcp", "telegram",
                "--json"
            ]
        )
        XCTAssertEqual(globalRes.exitCode, 0)
        let updatedGlobal = await vault.loadGlobalSelection()
        XCTAssertTrue(updatedGlobal.enabledMCPServerIds.contains("telegram"))
    }

    // MARK: - 3. SessionStart Hook Tests (Antigravity & Claude Code)
    func testCLIRunnerHookSessionStartAntigravityAndClaudeFormats() async throws {
        try await seedVaultCatalog()
        let projDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("radar-test-app", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet p = Package(name: \"radar\", platforms: [.macOS(.v14)])"
            .write(to: projDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let vault = VaultService()
        await vault.saveProjects([ProjectProfile(id: "radar-test-app", name: "radar-test-app", path: projDir.path)])

        let stdinPayload: [String: Any] = [
            "conversationId": "conv-123",
            "workspacePaths": [projDir.path]
        ]
        let stdinData = try JSONSerialization.data(withJSONObject: stdinPayload)

        // 1. Antigravity format
        let agyRes = await CLIRunner.execute(
            arguments: ["agymg", "hook-session-start", "--format", "antigravity"],
            stdinData: stdinData
        )
        XCTAssertEqual(agyRes.exitCode, 0)
        let jsonObj = try JSONSerialization.jsonObject(with: Data(agyRes.stdout.utf8)) as? [String: Any]
        let injectSteps = jsonObj?["injectSteps"] as? [[String: Any]]
        XCTAssertEqual(injectSteps?.count, 1)
        let sysMsgObj = injectSteps?.first?["systemMessage"] as? [String: Any]
        let modelMsg = sysMsgObj?["systemMessage"] as? String ?? ""

        XCTAssertNil(
            sysMsgObj?["metadata"],
            "Antigravity 2.0 language_server ScrubInternalFields panics on HookSystemMessage.metadata map<string, string>"
        )
        XCTAssertTrue(modelMsg.contains("> 📦 **radar-test-app**"), "Model systemMessage must embed first-turn UI banner with project name")
        XCTAssertTrue(modelMsg.contains("> 💡 **Vault Suggestion:**"), "Model systemMessage must show proactive suggestion for empty Swift project")
        XCTAssertTrue(modelMsg.contains("build-macos-apps"), "Model systemMessage must include recommended resources")
        XCTAssertFalse(agyRes.stdout.contains("ghp_SUPER_SECRET_TOKEN_111"), "Hook output must never leak tokens")

        // Verify active_context.json was written
        let savedContext = await vault.loadActiveContext()
        XCTAssertEqual(savedContext?.projectId, "radar-test-app")
        XCTAssertEqual(savedContext?.projectPath, projDir.path)

        // 2. Claude text format + snake_case workspace_paths with file:// URI
        let claudeStdin = try JSONSerialization.data(withJSONObject: ["workspace_paths": ["file://\(projDir.path)"]])
        let claudeRes = await CLIRunner.execute(
            arguments: ["agymg", "hook-session-start", "--format", "claude-text"],
            stdinData: claudeStdin
        )
        XCTAssertEqual(claudeRes.exitCode, 0)
        XCTAssertTrue(claudeRes.stdout.contains("# Antigravity Vault Radar"))
        XCTAssertTrue(claudeRes.stdout.contains("radar-test-app"))
    }

    // MARK: - 4. ActiveWorkspaceMonitor & AppState Auto-Follow / Menubar UI Tests
    func testActiveWorkspaceMonitorStorageJSONParsingAndAutoFollow() async throws {
        let storageJSON = """
        {
          "windowsState": {
            "lastActiveWindow": {
              "folder": "file:///Users/dev/Projects/acme-web",
              "backupPath": "/tmp/backup"
            }
          }
        }
        """
        let extracted = ActiveWorkspaceMonitor.extractActiveFolder(fromStorageJSONData: Data(storageJSON.utf8))
        XCTAssertEqual(extracted, "/Users/dev/Projects/acme-web")

        let state = AppState(autoload: false)
        let projA = ProjectProfile(id: "acme-web", name: "acme-web", path: "/Users/dev/Projects/acme-web")
        let projB = ProjectProfile(id: "docs-portal", name: "docs-portal", path: "/Users/dev/Projects/docs-portal")
        state.projects = [projA, projB]
        state.selectedProjectId = "docs-portal"

        // With autoFollowWorkspace = true, applyDetectedWorkspace switches selectedProjectId
        state.autoFollowWorkspace = true
        let matched = state.applyDetectedWorkspace(
            path: "/Users/dev/Projects/acme-web/src/pages",
            source: "ide-focus"
        )
        XCTAssertEqual(matched?.id, "acme-web")
        XCTAssertEqual(state.selectedProjectId, "acme-web")

        // With autoFollowWorkspace = false (LOCKED), applyDetectedWorkspace does not override user selection
        state.autoFollowWorkspace = false
        let ignored = state.applyDetectedWorkspace(
            path: "/Users/dev/Projects/docs-portal",
            source: "ide-focus"
        )
        XCTAssertNil(ignored)
        XCTAssertEqual(state.selectedProjectId, "acme-web", "Locked mode must preserve selectedProjectId")
        state.cancelPendingTasks()
    }

    func testMenuBarRecommendationsAndTabsRendering() {
        let state = AppState(autoload: false)
        let proj = ProjectProfile(id: "demo-proj", name: "DemoProj", path: "/tmp/demo-proj")
        state.projects = [proj]
        state.selectedProjectId = "demo-proj"
        state.projectStackLabels["demo-proj"] = ["Swift / macOS"]
        state.servers = (1...12).map { i in
            MCPServerDefinition(id: "srv-\(i)", name: "Server \(i)", category: "General", config: [:])
        }
        state.globalServerIds = ["srv-1", "srv-2"]

        // Empty project with 0 recommendations renders neutral info banner
        let emptyProjSection = MenuBarRecommendationsSection(
            state: state,
            projectId: "demo-proj",
            recommendations: [],
            stackLabels: ["Swift / macOS"]
        )
        XCTAssertNotNil(emptyProjSection.body)

        let recMCP = ResourceRecommendation(id: "supabase", name: "Supabase", kind: .mcp, reason: "Detected Supabase", priority: .high)
        let recSkill = ResourceRecommendation(id: "ui-architect", name: "UI Architect", kind: .skill, reason: "Detected React", priority: .medium)
        state.projectRecommendations["demo-proj"] = [recMCP, recSkill]

        XCTAssertTrue(state.hasActiveProjectRecommendations)
        XCTAssertNotNil(MenuBarIconProvider.icon(hasRecommendations: true))
        XCTAssertNotNil(MenuBarIconProvider.icon(hasRecommendations: false))

        let recSection = MenuBarRecommendationsSection(
            state: state,
            projectId: "demo-proj",
            recommendations: [recMCP, recSkill],
            stackLabels: ["Swift / macOS"]
        )
        XCTAssertNotNil(recSection.body)

        // Enabling a recommendation updates project and removes it from projectRecommendations
        state.enableRecommendedResource(recMCP, for: "demo-proj")
        XCTAssertTrue(state.projects[0].enabledMCPServerIds.contains("supabase"))
        XCTAssertEqual(state.projectRecommendations["demo-proj"]?.count, 1)

        // Enable remaining recommendations
        state.enableAllRecommendations(for: "demo-proj")
        XCTAssertTrue(state.projects[0].enabledSkillIds.contains("ui-architect"))
        XCTAssertFalse(state.hasActiveProjectRecommendations)

        // All-active banner when 0 missing recommendations remain and project has enabled resources
        let allActiveSection = MenuBarRecommendationsSection(
            state: state,
            projectId: "demo-proj",
            recommendations: [],
            stackLabels: ["Swift / macOS"]
        )
        XCTAssertNotNil(allActiveSection.body)

        let skill = SkillDefinition(id: "ui-architect", name: "UI Architect", description: "UI", path: "/tmp/ui")
        let plugin = PluginDefinition(id: "modern-web", name: "Modern Web", description: "Web", path: "/tmp/mw")
        state.skills = [skill]
        state.plugins = [plugin]

        let skillRow = MenuBarSkillRow(state: state, skill: skill, projectId: "demo-proj")
        let pluginRow = MenuBarPluginRow(state: state, plugin: plugin, projectId: "demo-proj")
        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(skillRow.body)
        XCTAssertNotNil(pluginRow.body)
        XCTAssertNotNil(popover.body)

        // Verify NSHostingView intrinsic fittingSize does not collapse the ScrollView
        let hostingView = NSHostingView(rootView: popover)
        let fittingSize = hostingView.fittingSize
        XCTAssertEqual(fittingSize.width, DesignTokens.Dimensions.popoverWidth, accuracy: 2.0)
        XCTAssertGreaterThanOrEqual(
            fittingSize.height,
            420.0,
            "MenuBarPopoverView fittingSize.height (\(fittingSize.height)) must include full ScrollView height (224pt) and never collapse to ~12px"
        )

        state.cancelPendingTasks()
    }

    // MARK: - 5. Edge Cases: Malformed Inputs, Unregistered Git Repos & Error Paths
    func testEdgeCasesMalformedInputsUnregisteredProjectsAndErrorPaths() async throws {
        try await seedVaultCatalog()
        let service = ProjectRecommendationService()

        // 1. Non-existent directory stack inspection must not crash and must return empty signals
        let missingStack = service.inspectStack(at: "/non/existent/path/\(UUID().uuidString)")
        XCTAssertFalse(missingStack.hasPackageJson)
        XCTAssertFalse(missingStack.hasSwiftPackage)
        XCTAssertTrue(missingStack.stackLabels.isEmpty)

        // 2. Corrupted package.json must not crash and must still detect file presence gracefully
        let badPkgDir = sandboxDir.appendingPathComponent("corrupted-pkg", isDirectory: true)
        try fm.createDirectory(at: badPkgDir, withIntermediateDirectories: true)
        try "{not valid json at all!!!".write(
            to: badPkgDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        let badPkgStack = service.inspectStack(at: badPkgDir.path)
        XCTAssertTrue(badPkgStack.hasPackageJson)
        XCTAssertFalse(badPkgStack.hasWebFrontendMarker)

        // 3. Unregistered git repo walked up from nested subdirectory
        let unregRoot = sandboxDir.appendingPathComponent("unregistered-repo", isDirectory: true)
        let nestedDir = unregRoot.appendingPathComponent("packages/web/src", isDirectory: true)
        try fm.createDirectory(at: unregRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let (resolvedProj, isRegistered) = CLIRunner.resolveOrCreateProject(for: nestedDir.path, in: [])
        XCTAssertFalse(isRegistered)
        XCTAssertEqual(resolvedProj.name, "unregistered-repo")
        XCTAssertEqual(
            URL(fileURLWithPath: resolvedProj.path).resolvingSymlinksInPath().path,
            unregRoot.resolvingSymlinksInPath().path
        )

        // 4. Unknown CLI subcommand and empty `set` invocation return non-zero exit codes
        let unknownCmd = await CLIRunner.execute(arguments: ["agymg", "non-existent-subcommand"])
        XCTAssertNotEqual(unknownCmd.exitCode, 0)
        XCTAssertFalse(unknownCmd.stderr.isEmpty)

        let emptySetCmd = await CLIRunner.execute(arguments: ["agymg", "set", "--project", unregRoot.path])
        XCTAssertNotEqual(emptySetCmd.exitCode, 0)

        // 5. `agymg set` with unknown resource IDs populates skippedUnknownIds and auto-registers project
        let setWithUnknowns = await CLIRunner.execute(
            arguments: [
                "agymg", "set",
                "--project", nestedDir.path,
                "--enable-mcp", "supabase,nonexistent-mcp-xyz",
                "--enable-skill", "nonexistent-skill-xyz",
                "--json"
            ]
        )
        XCTAssertEqual(setWithUnknowns.exitCode, 0)
        let decodedSet = try JSONDecoder().decode(CLISetResponse.self, from: Data(setWithUnknowns.stdout.utf8))
        XCTAssertTrue(decodedSet.enabledMCPs.contains("supabase"))
        XCTAssertTrue(decodedSet.unknownIds.contains("mcp:nonexistent-mcp-xyz"))
        XCTAssertTrue(decodedSet.unknownIds.contains("skill:nonexistent-skill-xyz"))

        // 6. `hook-session-start` with malformed/empty stdin falls back gracefully to currentDirectoryPath
        let malformedStdinRes = await CLIRunner.execute(
            arguments: ["agymg", "hook-session-start", "--format", "antigravity"],
            stdinData: Data("{broken json".utf8),
            currentDirectoryPath: unregRoot.path
        )
        XCTAssertEqual(malformedStdinRes.exitCode, 0)
        XCTAssertTrue(malformedStdinRes.stdout.contains("injectSteps"))

        // 7. ActiveWorkspaceMonitor.extractActiveFolder with empty/corrupted JSON
        XCTAssertNil(ActiveWorkspaceMonitor.extractActiveFolder(fromStorageJSONData: Data()))
        XCTAssertNil(ActiveWorkspaceMonitor.extractActiveFolder(fromStorageJSONData: Data("not-json".utf8)))
    }

    // MARK: - 6. Regression Tests: iOS-Only Filtering, Multi-Profile IDE Focus, Open-Pipe Stdin & Concurrent CLI/GUI
    func testIOSOnlyXcodeProjectDoesNotRecommendMacOSOnlyPluginAndEmitsEmptySetupRadar() async throws {
        try await seedVaultCatalog()
        let iosProjDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("mobile-client", isDirectory: true)
        let xcodeprojDir = iosProjDir.appendingPathComponent("MobileClient.xcodeproj", isDirectory: true)
        try fm.createDirectory(at: xcodeprojDir, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;\nIPHONEOS_DEPLOYMENT_TARGET = 17.0;".write(
            to: xcodeprojDir.appendingPathComponent("project.pbxproj"),
            atomically: true,
            encoding: .utf8
        )

        let vault = VaultService()
        // Include a stale non-existent skill ID in enabledSkillIds to verify isEmptyProjectSetup still detects 0 resolved resources
        let profile = ProjectProfile(
            id: "mobile-client",
            name: "mobile-client",
            path: iosProjDir.path,
            enabledSkillIds: ["stale-deleted-skill-id"]
        )
        await vault.saveProjects([profile])

        let briefRes = await CLIRunner.execute(
            arguments: ["agymg", "brief", "--project", iosProjDir.path, "--json"]
        )
        XCTAssertEqual(briefRes.exitCode, 0)
        let decoded = try JSONDecoder().decode(CLIBriefResponse.self, from: Data(briefRes.stdout.utf8))
        XCTAssertTrue(decoded.project.stackLabels.contains("Xcode / iOS"))
        XCTAssertTrue(decoded.project.isEmptyProjectSetup, "Stale non-existent skill IDs must not mask an empty project setup")
        XCTAssertFalse(
            decoded.recommendations.contains(where: { $0.id == "build-macos-apps" }),
            "macOS-only plugin build-macos-apps must NOT be recommended for iOS-only Xcode projects"
        )

        let hookRes = await CLIRunner.execute(
            arguments: ["agymg", "hook-session-start", "--format", "claude-text", "--project", iosProjDir.path]
        )
        XCTAssertEqual(hookRes.exitCode, 0)
        XCTAssertTrue(hookRes.stdout.contains("detected Xcode / iOS project (0 active project MCPs/skills)"))
    }

    func testActiveWorkspaceMonitorAppSpecificProfileAndCursorResolution() async throws {
        let proj1Dir = PathConstants.desktopProjectsDirectory.appendingPathComponent("proj-profile1", isDirectory: true)
        let proj4Dir = PathConstants.desktopProjectsDirectory.appendingPathComponent("proj-profile4", isDirectory: true)
        let projCursorDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("proj-cursor", isDirectory: true)
        let projChatDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("proj-chat", isDirectory: true)
        for d in [proj1Dir, proj4Dir, projCursorDir, projChatDir] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }

        let home = PathConstants.effectiveHomeDirectory
        let p1Storage = home.appendingPathComponent("Library/Application Support/Antigravity IDE/User/globalStorage/storage.json")
        let p4Storage = home.appendingPathComponent("AntigravityProfiles/Profile4/ide-data/User/globalStorage/storage.json")
        let cursorStorage = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/storage.json")

        for fileURL in [p1Storage, p4Storage, cursorStorage] {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        try #"{"windowsState":{"lastActiveWindow":{"folder":"file://\#(proj1Dir.path)"}}}"#
            .write(to: p1Storage, atomically: true, encoding: .utf8)
        try #"{"windowsState":{"lastActiveWindow":{"folder":"file://\#(proj4Dir.path)"}}}"#
            .write(to: p4Storage, atomically: true, encoding: .utf8)
        try #"{"windowsState":{"lastActiveWindow":{"folder":"file://\#(projCursorDir.path)"}}}"#
            .write(to: cursorStorage, atomically: true, encoding: .utf8)

        // Write a NEWER active_context.json to simulate a recent chat session in another app
        let vault = VaultService()
        await vault.saveActiveContext(ActiveWorkspaceContext(
            projectPath: projChatDir.path,
            projectId: "proj-chat",
            projectName: "proj-chat",
            source: "session-start",
            updatedAt: Date().addingTimeInterval(60)
        ))

        // Verify isRelevantIDE filters out utility apps
        XCTAssertFalse(ActiveWorkspaceMonitor.isRelevantIDE(bundleId: "com.nikolastanojevic.agymg", appName: "agymg"))
        XCTAssertFalse(ActiveWorkspaceMonitor.isRelevantIDE(bundleId: "com.example.antigravity-monitor", appName: "Antigravity Monitor"))
        XCTAssertTrue(ActiveWorkspaceMonitor.isRelevantIDE(bundleId: "com.google.antigravity-ide.profile4", appName: "Antigravity IDE"))

        // Focusing Antigravity IDE Profile 4 resolves proj4Dir even though active_context.json is newer
        let resolvedP4 = ActiveWorkspaceMonitor.detectWorkspaceForApp(
            bundleId: "com.google.antigravity-ide.profile4",
            appName: "Antigravity IDE",
            home: home
        )
        XCTAssertEqual(resolvedP4?.path, proj4Dir.path)

        // Focusing Antigravity IDE Profile 1 resolves proj1Dir
        let resolvedP1 = ActiveWorkspaceMonitor.detectWorkspaceForApp(
            bundleId: "com.google.antigravity-ide",
            appName: "Antigravity IDE",
            home: home
        )
        XCTAssertEqual(resolvedP1?.path, proj1Dir.path)

        // Focusing Cursor resolves projCursorDir
        let resolvedCursor = ActiveWorkspaceMonitor.detectWorkspaceForApp(
            bundleId: "com.todesktop.230313mzl4w4u92",
            appName: "Cursor",
            home: home
        )
        XCTAssertEqual(resolvedCursor?.path, projCursorDir.path)

        // Focusing Antigravity Agent Hub resolves active_context.json (projChatDir)
        let resolvedHub = ActiveWorkspaceMonitor.detectWorkspaceForApp(
            bundleId: "com.google.antigravity.profile4",
            appName: "Antigravity",
            home: home
        )
        XCTAssertEqual(resolvedHub?.path, projChatDir.path)
    }

    func testReadNonBlockingStdinDoesNotHangWhenPipeWriteEndRemainsOpen() throws {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(Darwin.pipe(&fds), 0)
        let readFD = fds[0]
        let writeFD = fds[1]
        defer {
            Darwin.close(readFD)
            Darwin.close(writeFD)
        }

        // Write payload WITHOUT closing writeFD (simulating a parent process that keeps stdin pipe open)
        let payload = #"{"cwd":"/tmp/open-pipe-test"}"#
        payload.withCString { ptr in
            _ = Darwin.write(writeFD, ptr, strlen(ptr))
        }

        let start = CFAbsoluteTimeGetCurrent()
        let data = CLIRunner.readNonBlockingStdinIfPiped(from: readFD, initialTimeoutMs: 50)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data ?? Data(), encoding: .utf8), payload)
        XCTAssertLessThan(elapsed, 0.25, "readNonBlockingStdinIfPiped must return promptly without waiting for EOF")
    }

    func testReloadFromVaultAfterCLICancelsPendingGUIDebounceTasks() async throws {
        try await seedVaultCatalog()
        let projDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("race-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let vault = VaultService()
        await vault.saveProjects([ProjectProfile(id: "race-proj", name: "race-proj", path: projDir.path)])

        let state = AppState(autoload: false)
        await state.loadData()

        // 1. Trigger a debounced GUI project toggle (250ms debounce)
        state.toggleProjectServer(projectId: "race-proj", serverId: "polar")
        XCTAssertNotNil(state.projectSyncDebounceTasks["race-proj"])

        // 2. Before the 250ms GUI debounce fires, CLI mutates the same project to enable "supabase" instead
        let cliRes = await CLIRunner.execute(
            arguments: ["agymg", "set", "--project", projDir.path, "--enable-mcp", "supabase", "--json"]
        )
        XCTAssertEqual(cliRes.exitCode, 0)

        // 3. Menubar receives CLI mutation signal and reloads from Vault
        await state.reloadFromVaultAfterCLI(preferredProjectPath: projDir.path, source: "cli-set")
        XCTAssertTrue(state.projectSyncDebounceTasks.isEmpty, "Pending GUI debounce tasks must be cancelled upon CLI reload")

        // Wait past the original 250ms debounce window and verify the CLI's change was NOT overwritten
        try await Task.sleep(nanoseconds: 300_000_000)
        let finalProj = state.projects.first(where: { $0.id == "race-proj" })
        XCTAssertEqual(finalProj?.enabledMCPServerIds, ["supabase"])
        state.cancelPendingTasks()
    }
}
