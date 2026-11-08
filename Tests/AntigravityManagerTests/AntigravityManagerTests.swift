import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

@MainActor
final class AntigravityManagerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AntigravityTests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        tempDir = dir
        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    // MARK: - HIG 8pt Grid & Spacing Tests
    func testDesignTokensSpacingHIGCompliance() {
        let spacings: [CGFloat] = [
            DesignTokens.Spacing.xxs,
            DesignTokens.Spacing.xs,
            DesignTokens.Spacing.sm,
            DesignTokens.Spacing.md,
            DesignTokens.Spacing.lg,
            DesignTokens.Spacing.xl,
            DesignTokens.Spacing.xxl,
            DesignTokens.Spacing.hero
        ]

        // Apple HIG & AGENTS rule: Every spacing must be a multiple of 4
        for spacing in spacings {
            XCTAssertEqual(
                spacing.truncatingRemainder(dividingBy: 4), 0,
                "Spacing \(spacing) violates the 4pt/8pt grid requirement!"
            )
        }

        // Verify prohibited arbitrary values
        let prohibitedValues: Set<CGFloat> = [7, 11, 13, 17, 23]
        for spacing in spacings {
            XCTAssertFalse(
                prohibitedValues.contains(spacing),
                "Spacing \(spacing) is in the prohibited arbitrary spacing list!"
            )
        }
    }

    // MARK: - Bjango & HIG MenuBarIcon Tests
    func testMenuBarIconDimensionsAndTemplate() {
        guard let icon = MenuBarIconProvider.icon else {
            XCTFail("MenuBarIconProvider.icon must not be nil")
            return
        }

        // Bjango & Apple HIG: Menu bar icon canvas must be 18x18 pt
        XCTAssertEqual(icon.size.width, 18, accuracy: 0.1, "Icon width must be 18pt")
        XCTAssertEqual(icon.size.height, 18, accuracy: 0.1, "Icon height must be 18pt")

        // HIG: Must be template image for automatic Dark/Light appearance
        XCTAssertTrue(icon.isTemplate, "MenuBar icon must have isTemplate = true")
    }

    // MARK: - App Review 2.4.5 & Launch at Login Tests
    func testLaunchAtLoginManagerBehavior() {
        let manager = LaunchAtLoginManager.shared

        // Ensure refresh does not crash
        manager.refresh()

        // Verify description is non-empty and user-friendly
        let desc = manager.statusDescription
        XCTAssertFalse(desc.isEmpty, "Status description must be non-empty")

        // If not installed in /Applications, verify helpful description
        if !manager.isInstalledInApplications && manager.status == .notFound {
            XCTAssertTrue(desc.contains("/Applications"), "Status description must guide user about /Applications location")
        }
    }

    // MARK: - Commands & State Navigation Tests
    func testCommandsInstantiationAndNavigation() {
        let state = AppState()
        let _ = AntigravityCommands(state: state)

        // Verify state initial navigation selection
        XCTAssertEqual(state.navigationSelection, .masterVault)

        // Verify switching navigation section
        state.navigationSelection = .globalCore
        XCTAssertEqual(state.navigationSelection, .globalCore)

        state.navigationSelection = .plugins
        XCTAssertEqual(state.navigationSelection, .plugins)
        state.cancelPendingTasks()
    }

    // MARK: - Window Router Popover Dismissal & Reopen
    func testWindowRouterDismissPopover() {
        // WindowRouter.dismissPopover should execute cleanly without crashing
        WindowRouter.dismissPopover()
    }

    func testWindowRouterTriggerOpenInvokesCallback() {
        var called = false
        WindowRouter.openControlCenter = {
            called = true
        }

        WindowRouter.triggerOpen()
        XCTAssertTrue(called, "WindowRouter.triggerOpen must invoke openControlCenter closure when no window is open")
    }

    func testAppDelegateShouldHandleReopenActivatesAndOpensWindow() {
        let delegate = AppDelegate()
        var opened = false
        WindowRouter.openControlCenter = {
            opened = true
        }

        let handled = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        XCTAssertTrue(handled, "AppDelegate.applicationShouldHandleReopen must return true")
        XCTAssertTrue(opened, "AppDelegate must synchronously trigger WindowRouter.triggerOpen on reopen")
    }

    func testMenuBarPopoverMinimalViewInstantiation() {
        let state = AppState()
        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover)
        state.cancelPendingTasks()
    }

    // MARK: - Project Folder Access & Authorization Lifecycle Tests
    func testProjectFolderAccessManagerAuthorizationLifecycle() {
        let manager = ProjectFolderAccessManager.shared
        let originalAuthorized = manager.isAuthorized

        // Test resetting authorization
        manager.resetAuthorization()
        XCTAssertFalse(manager.isAuthorized, "isAuthorized should be false after reset")
        XCTAssertFalse(manager.hasSavedBookmark, "hasSavedBookmark should be false after reset")

        // Test saving authorization with temporary URL
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("AntigravityTestProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        manager.saveAuthorization(url: tempURL)
        XCTAssertTrue(manager.isAuthorized, "isAuthorized should be true after saveAuthorization")
        XCTAssertEqual(manager.targetDirectoryURL.path, tempURL.path, "targetDirectoryURL should match saved URL")

        // Clean up / restore
        if originalAuthorized {
            manager.saveAuthorization(url: PathConstants.desktopProjectsDirectory)
        } else {
            manager.resetAuthorization()
        }
    }

    func testAppStateOnboardingStateHandling() {
        let state = AppState()
        let originalAuth = state.isProjectsFolderAuthorized

        state.isProjectsFolderAuthorized = false
        XCTAssertFalse(state.isProjectsFolderAuthorized)

        state.resetProjectsFolderAuthorization()
        XCTAssertFalse(state.isProjectsFolderAuthorized)
        XCTAssertTrue(state.projects.isEmpty)

        // Restore
        state.isProjectsFolderAuthorized = originalAuth
        state.cancelPendingTasks()
    }

    func testOnboardingViewsInstantiation() {
        let state = AppState()
        let onboardingView = ProjectFolderOnboardingView(state: state)
        XCTAssertNotNil(onboardingView)

        let headerView = OnboardingHeaderView()
        XCTAssertNotNil(headerView)

        let featureList = OnboardingFeatureList()
        XCTAssertNotNil(featureList)

        let featureRow = OnboardingFeatureRow(
            icon: "sparkles",
            iconColor: .green,
            title: "Test Feature",
            description: "Test Description"
        )
        XCTAssertNotNil(featureRow)

        let successBadge = OnboardingSuccessBadge(
            projectCount: 4,
            projectNames: ["AcmeWeb", "iOSApp", "DocsPortal", "APIServer"]
        ) {}
        XCTAssertNotNil(successBadge)
        state.cancelPendingTasks()
    }

    func testAppStateApplyAuthorizedDirectoryDeferredAndImmediateState() async {
        let state = AppState(autoload: false)
        let fm = FileManager.default
        let tempProjectsDir = fm.temporaryDirectory.appendingPathComponent("TestProjects_\(UUID().uuidString)", isDirectory: true)
        let sampleProjectDir = tempProjectsDir.appendingPathComponent("sample-proj", isDirectory: true)
        let samplePluginDir = sampleProjectDir.appendingPathComponent(".agents/plugins/sample-mcp", isDirectory: true)

        try? fm.createDirectory(at: samplePluginDir, withIntermediateDirectories: true)
        let dummyMCP = "{\"mcpServers\": {\"dummy-server\": {\"command\": \"node\"}}}"
        try? dummyMCP.write(to: samplePluginDir.appendingPathComponent("mcp_config.json"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: tempProjectsDir) }

        // Test deferred authorization: updateAuthorizationState = false (for showing OnboardingSuccessBadge)
        state.isProjectsFolderAuthorized = false
        await state.applyAuthorizedDirectory(url: tempProjectsDir, updateAuthorizationState: false)

        XCTAssertFalse(state.isProjectsFolderAuthorized, "isProjectsFolderAuthorized must remain false while OnboardingSuccessBadge is active")
        let sample = state.projects.first(where: { $0.name == "sample-proj" })
        XCTAssertNotNil(sample, "Must discover sample-proj in directory")
        XCTAssertTrue(sample?.enabledMCPServerIds.contains("dummy-server") ?? false)

        // Simulate user clicking 'Open Control Center' in the badge
        state.isProjectsFolderAuthorized = true
        XCTAssertTrue(state.isProjectsFolderAuthorized)
        state.cancelPendingTasks()
    }

    func testVaultServiceDoesNotTouchProjectsWhenUnauthorized() async {
        let manager = ProjectFolderAccessManager.shared
        let originalAuth = manager.isAuthorized
        manager.resetAuthorization()
        defer {
            if originalAuth {
                manager.saveAuthorization(url: PathConstants.desktopProjectsDirectory)
            } else {
                manager.resetAuthorization()
            }
        }

        XCTAssertFalse(manager.isAuthorized)
        let vault = VaultService()
        let projects = await vault.loadProjects()
        XCTAssertTrue(projects.isEmpty, "loadProjects must return empty array when project folder is not authorized")
    }

    func testProjectFolderAccessManagerResolveBookmark() {
        let manager = ProjectFolderAccessManager.shared
        let originalAuth = manager.isAuthorized
        defer {
            if originalAuth {
                manager.saveAuthorization(url: PathConstants.desktopProjectsDirectory)
            } else {
                manager.resetAuthorization()
            }
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestBookmark_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        manager.saveAuthorization(url: tempDir)
        XCTAssertTrue(manager.hasSavedBookmark)
        let resolved = manager.resolveBookmark()
        XCTAssertNotNil(resolved, "resolveBookmark should successfully resolve saved bookmark")
    }

    func testPackageAppScriptContainsTCCAndDesignatedRequirements() {
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var scriptURL = currentDir.appendingPathComponent("Scripts/package_app.sh")
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            let fileURL = URL(fileURLWithPath: #filePath)
            scriptURL = fileURL
                .deletingLastPathComponent() // AntigravityManagerTests.swift
                .deletingLastPathComponent() // AntigravityManagerTests/
                .deletingLastPathComponent() // Tests/
                .appendingPathComponent("Scripts/package_app.sh")
        }

        guard let scriptContent = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            XCTFail("Could not read Scripts/package_app.sh at \(scriptURL.path)")
            return
        }

        XCTAssertTrue(
            scriptContent.contains("NSDesktopFolderUsageDescription"),
            "package_app.sh must contain NSDesktopFolderUsageDescription key in Info.plist"
        )
        XCTAssertTrue(
            scriptContent.contains("designated => identifier"),
            "package_app.sh must configure designated requirement with bundle identifier for stable ad-hoc codesigning"
        )
    }

    func testProjectDetailViewAndRuntimeManifestRendering() {
        let state = AppState()
        var project = ProjectProfile(
            id: "test-proj",
            name: "test-proj",
            path: FileManager.default.temporaryDirectory.path
        )
        project.enabledMCPServerIds = ["server-1", "server-2"]
        project.enabledSkillIds = ["skill-a", "skill-b", "skill-c"]
        project.enabledPluginIds = ["plugin-1"]

        state.projects = [project]
        state.selectedProjectId = project.id

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let detailView = ProjectDetailView(
            state: state,
            project: project,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )
        XCTAssertNotNil(detailView.body)

        let previewView = RuntimeManifestPreviewView(project: project, state: state)
        XCTAssertNotNil(previewView.body)
        state.cancelPendingTasks()
    }

    func testResourcePillBadgePresetsAndVaultBadges() {
        let singleScoped = ResourcePillBadge.scopedProjects(1)
        XCTAssertEqual(singleScoped.title, "1 PROJECT")
        XCTAssertTrue(singleScoped.isMonospaced)

        let multiScoped = ResourcePillBadge.scopedProjects(3)
        XCTAssertEqual(multiScoped.title, "3 PROJECTS")
        XCTAssertTrue(multiScoped.isMonospaced)

        let fiveScoped = ResourcePillBadge.scopedProjects(5)
        XCTAssertEqual(fiveScoped.title, "5 PROJECTS")
        XCTAssertTrue(fiveScoped.isMonospaced)

        let twentyOneScoped = ResourcePillBadge.scopedProjects(21)
        XCTAssertEqual(twentyOneScoped.title, "21 PROJECTS")

        let catalogBadge = ResourcePillBadge.catalogOnly
        XCTAssertEqual(catalogBadge.title, "CATALOG")
        XCTAssertTrue(catalogBadge.isMonospaced)
    }

    func testMasterVaultGuidanceBannerAndTabsRendering() {
        let state = AppState()
        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let bannerWithoutState = VaultGuidanceBannerView()
        XCTAssertNotNil(bannerWithoutState.body)

        let bannerWithState = VaultGuidanceBannerView(state: state)
        XCTAssertNotNil(bannerWithState.body)

        let vaultView = MasterVaultView(
            state: state,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )
        XCTAssertNotNil(vaultView.body)

        let serversTab = VaultServersTab(
            state: state,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 })
        )
        XCTAssertNotNil(serversTab.body)

        let skillsTab = VaultSkillsTab(
            state: state,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )
        XCTAssertNotNil(skillsTab.body)

        let pluginsTab = VaultPluginsTab(
            state: state,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 })
        )
        XCTAssertNotNil(pluginsTab.body)
        state.cancelPendingTasks()
    }

    func testGlobalCoreGuidanceBannerRendering() {
        let state = AppState()
        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let globalCore = GlobalCoreView(
            state: state,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )
        XCTAssertNotNil(globalCore.body)
        state.cancelPendingTasks()
    }

    func testProjectToggleUpdatesStateAndUIReactivity() {
        let state = AppState()
        let project = ProjectProfile(
            id: "test-proj",
            name: "Test Project",
            path: "/tmp/test-project",
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: []
        )
        state.projects = [project]

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        // Verify initial state
        XCTAssertFalse(state.projects[0].enabledMCPServerIds.contains("github"))
        XCTAssertFalse(state.projects[0].enabledSkillIds.contains("ask"))
        XCTAssertFalse(state.projects[0].enabledPluginIds.contains("chrome-devtools"))

        // Toggle server
        state.toggleProjectServer(projectId: "test-proj", serverId: "github")
        XCTAssertTrue(state.projects[0].enabledMCPServerIds.contains("github"))

        // Toggle skill
        state.toggleProjectSkill(projectId: "test-proj", skillId: "ask")
        XCTAssertTrue(state.projects[0].enabledSkillIds.contains("ask"))

        // Toggle plugin
        state.toggleProjectPlugin(projectId: "test-proj", pluginId: "chrome-devtools")
        XCTAssertTrue(state.projects[0].enabledPluginIds.contains("chrome-devtools"))

        // Test tabs instantiate with projectId and have non-nil body
        let serversTab = ProjectServersTab(
            state: state,
            projectId: "test-proj",
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 })
        )
        XCTAssertNotNil(serversTab.body)

        let skillsTab = ProjectSkillsTab(
            state: state,
            projectId: "test-proj",
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )
        XCTAssertNotNil(skillsTab.body)

        let pluginsTab = ProjectPluginsTab(
            state: state,
            projectId: "test-proj",
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 })
        )
        XCTAssertNotNil(pluginsTab.body)

        // Toggle off
        state.toggleProjectServer(projectId: "test-proj", serverId: "github")
        XCTAssertFalse(state.projects[0].enabledMCPServerIds.contains("github"))
        state.cancelPendingTasks()
    }

    func testHotKeyManagerRegistration() {
        HotKeyManager.shared.register()
        // Calling again is idempotent
        HotKeyManager.shared.register()
    }

    func testMenuBarPopoverAndServerRow() {
        let state = AppState()
        let server = MCPServerDefinition(id: "test-mcp", name: "Test MCP", category: "core", config: [:])
        state.servers = [server]

        let row = MenuBarServerRow(state: state, server: server)
        XCTAssertNotNil(row.body)

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body)
        state.cancelPendingTasks()
    }

    func testSkillEditorDirectoryFilteringAndCreation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a root skill file
        let skillMd = tempDir.appendingPathComponent("SKILL.md")
        try "# Test Skill".write(to: skillMd, atomically: true, encoding: .utf8)

        // Create references directory with a file and a subdirectory
        let refDir = tempDir.appendingPathComponent("references")
        try FileManager.default.createDirectory(at: refDir, withIntermediateDirectories: true)
        let refFile = refDir.appendingPathComponent("guide.md")
        try "# Guide".write(to: refFile, atomically: true, encoding: .utf8)
        let subDir = refDir.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let skill = SkillDefinition(
            id: "test-skill",
            name: "Test Skill",
            description: "Testing",
            category: "test",
            path: tempDir.path,
            origin: .vault
        )

        let editorState = SkillEditorState(skill: skill)
        editorState.discoverAndLoadFiles()

        // Verify assets directory is NOT in availableFiles
        XCTAssertFalse(editorState.availableFiles.contains(where: { $0.lastPathComponent == "assets" }))
        XCTAssertTrue(editorState.availableFiles.contains(where: { $0.lastPathComponent == "guide.md" }))
        XCTAssertTrue(editorState.availableFiles.contains(where: { $0.lastPathComponent == "SKILL.md" }))

        // Test saveChanges creates non-existent parent directory
        let newNestedFile = tempDir.appendingPathComponent("nested").appendingPathComponent("new.md")
        editorState.targetFileURL = newNestedFile
        editorState.content = "New nested content"
        editorState.saveChanges()

        XCTAssertTrue(FileManager.default.fileExists(atPath: newNestedFile.path))
        let saved = try String(contentsOf: newNestedFile, encoding: .utf8)
        XCTAssertEqual(saved, "New nested content")
    }

    func testDecomposedViewsInstantiation() {
        let state = AppState()
        let footer = VaultEngineFooterView()
        XCTAssertNotNil(footer.body)

        let banner = ProjectIsolationBannerView(projectName: "Demo")
        XCTAssertNotNil(banner.body)

        let general = SettingsGeneralTab(state: state)
        XCTAssertNotNil(general.body)

        let vault = SettingsVaultTab(state: state)
        XCTAssertNotNil(vault.body)

        let compliance = SettingsComplianceTab()
        XCTAssertNotNil(compliance.body)
        state.cancelPendingTasks()
    }

    // MARK: - Regression: ProjectProfile Value Equality & Hashing
    func testProjectProfileValueEquality() {
        let base = ProjectProfile(
            id: "proj-1",
            name: "Alpha Project",
            path: "/path/to/alpha",
            enabledMCPServerIds: ["server-a"],
            enabledSkillIds: ["skill-a"],
            enabledPluginIds: ["plugin-a"]
        )

        // 1. Identical instance must be equal and share hashValue
        let identical = ProjectProfile(
            id: "proj-1",
            name: "Alpha Project",
            path: "/path/to/alpha",
            enabledMCPServerIds: ["server-a"],
            enabledSkillIds: ["skill-a"],
            enabledPluginIds: ["plugin-a"]
        )
        XCTAssertEqual(base, identical)
        XCTAssertEqual(base.hashValue, identical.hashValue)

        // 2. Differing enabledMCPServerIds must evaluate not equal
        var diffServers = base
        diffServers.enabledMCPServerIds = ["server-a", "server-b"]
        XCTAssertNotEqual(base, diffServers, "Differing enabledMCPServerIds must make ProjectProfile unequal")

        // 3. Differing enabledSkillIds must evaluate not equal
        var diffSkills = base
        diffSkills.enabledSkillIds = ["skill-a", "skill-b"]
        XCTAssertNotEqual(base, diffSkills, "Differing enabledSkillIds must make ProjectProfile unequal")

        // 4. Differing enabledPluginIds must evaluate not equal
        var diffPlugins = base
        diffPlugins.enabledPluginIds = ["plugin-b"]
        XCTAssertNotEqual(base, diffPlugins, "Differing enabledPluginIds must make ProjectProfile unequal")

        // 5. Differing name must evaluate not equal
        var diffName = base
        diffName.name = "Beta Project"
        XCTAssertNotEqual(base, diffName, "Differing name must make ProjectProfile unequal")

        // 6. Differing path must evaluate not equal
        var diffPath = base
        diffPath.path = "/new/path"
        XCTAssertNotEqual(base, diffPath, "Differing path must make ProjectProfile unequal")

        // 7. Differing id must evaluate not equal
        var diffId = base
        diffId.id = "proj-2"
        XCTAssertNotEqual(base, diffId, "Differing id must make ProjectProfile unequal")
    }

    // MARK: - Regression: RuntimeManifestPreviewView Reactivity
    func testRuntimeManifestPreviewReactivity() {
        let state = AppState()
        let serverA = MCPServerDefinition(
            id: "mcp-alpha",
            name: "Alpha Server",
            category: "core",
            config: ["command": .string("node"), "args": .array([.string("alpha.js")])]
        )
        let serverB = MCPServerDefinition(
            id: "mcp-beta",
            name: "Beta Server",
            category: "tools",
            config: ["command": .string("python"), "args": .array([.string("beta.py")])]
        )
        state.servers = [serverA, serverB]

        let initialProject = ProjectProfile(
            id: "proj-reactivity-test",
            name: "Reactivity Test Project",
            path: "/tmp/reactivity-test",
            enabledMCPServerIds: ["mcp-alpha"],
            enabledSkillIds: ["skill-x"],
            enabledPluginIds: []
        )
        state.projects = [initialProject]

        // 1. Initial preview contains mcp-alpha but not mcp-beta
        let initialView = RuntimeManifestPreviewView(project: initialProject, state: state)
        let initialJSON = initialView.manifestJSON
        XCTAssertTrue(initialJSON.contains("mcp-alpha"))
        XCTAssertFalse(initialJSON.contains("mcp-beta"))
        XCTAssertTrue(initialJSON.contains("skill-x"))

        // 2. Toggle mcp-beta in project
        state.toggleProjectServer(projectId: initialProject.id, serverId: "mcp-beta")
        guard let updatedProject = state.projects.first(where: { $0.id == initialProject.id }) else {
            XCTFail("Project must exist in state after toggle")
            return
        }

        // ProjectProfile value equality must fail so SwiftUI .task(id: project) detects change
        XCTAssertNotEqual(
            initialProject, updatedProject,
            "Toggled project must NOT equal initial project, enabling SwiftUI .task(id: project) execution"
        )

        // 3. Updated preview reflects newly toggled server
        let updatedView = RuntimeManifestPreviewView(project: updatedProject, state: state)
        let updatedJSON = updatedView.manifestJSON
        XCTAssertTrue(updatedJSON.contains("mcp-alpha"))
        XCTAssertTrue(updatedJSON.contains("mcp-beta"))
        XCTAssertNotEqual(initialJSON, updatedJSON, "Manifest JSON must update when servers are toggled")

        // 4. Toggle off mcp-alpha
        state.toggleProjectServer(projectId: initialProject.id, serverId: "mcp-alpha")
        guard let finalProject = state.projects.first(where: { $0.id == initialProject.id }) else {
            XCTFail("Project must exist in state after second toggle")
            return
        }
        let finalView = RuntimeManifestPreviewView(project: finalProject, state: state)
        let finalJSON = finalView.manifestJSON
        XCTAssertFalse(finalJSON.contains("mcp-alpha"))
        XCTAssertTrue(finalJSON.contains("mcp-beta"))
        state.cancelPendingTasks()
    }

    // MARK: - Regression: RuntimeManifestPreviewView Regenerate Button Action
    func testRuntimeManifestPreviewRegenerateAction() async throws {
        let state = AppState()
        var server = MCPServerDefinition(
            id: "dynamic-server",
            name: "Dynamic Server",
            category: "core",
            config: ["command": .string("node"), "args": .array([.string("v1.js")])]
        )
        state.servers = [server]

        let project = ProjectProfile(
            id: "proj-regen-test",
            name: "Regen Project",
            path: "/tmp/regen-test",
            enabledMCPServerIds: ["dynamic-server"],
            enabledSkillIds: [],
            enabledPluginIds: []
        )
        state.projects = [project]

        let previewView = RuntimeManifestPreviewView(project: project, state: state)
        let initialJSON = previewView.manifestJSON
        XCTAssertTrue(initialJSON.contains("v1.js"))

        // Update server config in state
        server.config = ["command": .string("bun"), "args": .array([.string("v2_regenerated.ts")])]
        state.servers = [server]

        // Trigger Regenerate action
        previewView.handleRegenerate()

        // Verify updated manifest JSON
        let refreshedJSON = RuntimeManifestPreviewView.generateManifestJSON(project: project, servers: state.servers)
        XCTAssertTrue(refreshedJSON.contains("v2_regenerated.ts"))
        XCTAssertTrue(refreshedJSON.contains("bun"))
        XCTAssertNotEqual(initialJSON, refreshedJSON)

        // Give background Task a moment to update statusMessage
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Verify sync feedback was posted
        XCTAssertTrue(
            state.statusMessage?.contains("Synchronized project: Regen Project") == true,
            "handleRegenerate must trigger state.triggerProjectSync"
        )
        state.cancelPendingTasks()
    }
}
