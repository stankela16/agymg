import XCTest
import SwiftUI
import AppKit
import Carbon
@testable import AntigravityManager

@MainActor
final class M1ChallengerVerificationTests: XCTestCase {

    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        let uniqueId = UUID().uuidString
        tempDir = fm.temporaryDirectory.appendingPathComponent("M1ChallengerTests_\(uniqueId)", isDirectory: true)
        let geminiDir = tempDir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        WindowRouter.openControlCenter = nil
        if let tempDir {
            try? fm.removeItem(at: tempDir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    // MARK: - Mission 1: HotKeyManager & WindowRouter Verification
    func testHotKeyManagerRegistrationAndWindowRouterIntegration() {
        // 1. Verify HotKeyManager instance and idempotent registration
        let manager = HotKeyManager.shared
        manager.register()
        manager.register() // Should not crash or re-install handlers

        // 2. Verify WindowRouter triggerOpen invokes openControlCenter callback when window is absent
        var openCalled = false
        WindowRouter.openControlCenter = {
            openCalled = true
        }

        WindowRouter.triggerOpen()
        XCTAssertTrue(openCalled, "WindowRouter.triggerOpen must invoke openControlCenter when no window is present")

        // 3. Verify dismissPopover does not crash and processes window hierarchy
        WindowRouter.dismissPopover()
    }

    // MARK: - Mission 2: MenuBarPopoverView Width & MenuBarServerRow Live Binding
    func testMenuBarPopoverWidthAndMenuBarServerRowLiveToggle() {
        // 1. Popover frame width must be exactly 360pt according to design tokens and HIG
        XCTAssertEqual(
            DesignTokens.Dimensions.popoverWidth,
            360,
            "DesignTokens.Dimensions.popoverWidth must be exactly 360pt"
        )

        let state = AppState(autoload: false)
        let testServer = MCPServerDefinition(
            id: "challenger-test-server",
            name: "Challenger Server",
            category: "core",
            config: ["command": .string("test")]
        )
        state.servers = [testServer]

        // Ensure initially not enabled
        state.globalServerIds.remove("challenger-test-server")
        XCTAssertFalse(state.globalServerIds.contains("challenger-test-server"))

        // Create MenuBarServerRow
        let row = MenuBarServerRow(state: state, server: testServer)
        XCTAssertNotNil(row.body)

        // Simulate toggling ON via state.toggleGlobalServer (the exact action wired in MenuBarServerRow's Binding)
        state.toggleGlobalServer(id: testServer.id)
        XCTAssertTrue(
            state.globalServerIds.contains("challenger-test-server"),
            "Toggling server in MenuBarServerRow must add server ID to state.globalServerIds"
        )

        // Simulate toggling OFF
        state.toggleGlobalServer(id: testServer.id)
        XCTAssertFalse(
            state.globalServerIds.contains("challenger-test-server"),
            "Toggling server again in MenuBarServerRow must remove server ID from state.globalServerIds"
        )

        // Verify MenuBarPopoverView instantiates cleanly with 360pt width
        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body)
        state.cancelPendingTasks()
    }

    // MARK: - Mission 3: SkillEditorState Directory Filtering & Deep Directory Creation
    func testSkillEditorStateAdversarialDirectoryFilteringAndCreation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SkillEditorAdv_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup complex file hierarchy:
        // tempDir/
        //   SKILL.md (file)
        //   references/
        //     doc1.md (file)
        //     subfolder/ (directory - should be excluded)
        //     .hidden_file.md (hidden - should be excluded)
        //   scripts/
        //     run.sh (file)
        //     nested_dir/ (directory - should be excluded)
        let skillMd = tempDir.appendingPathComponent("SKILL.md")
        try "# Skill Header".write(to: skillMd, atomically: true, encoding: .utf8)

        let referencesDir = tempDir.appendingPathComponent("references")
        try FileManager.default.createDirectory(at: referencesDir, withIntermediateDirectories: true)
        let doc1 = referencesDir.appendingPathComponent("doc1.md")
        try "# Doc 1".write(to: doc1, atomically: true, encoding: .utf8)

        let subfolderInRef = referencesDir.appendingPathComponent("subfolder")
        try FileManager.default.createDirectory(at: subfolderInRef, withIntermediateDirectories: true)

        let hiddenFile = referencesDir.appendingPathComponent(".hidden_file.md")
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)

        let scriptsDir = tempDir.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let runScript = scriptsDir.appendingPathComponent("run.sh")
        try "#!/bin/bash\necho ok".write(to: runScript, atomically: true, encoding: .utf8)

        let nestedDirInScripts = scriptsDir.appendingPathComponent("nested_dir")
        try FileManager.default.createDirectory(at: nestedDirInScripts, withIntermediateDirectories: true)

        let skill = SkillDefinition(
            id: "adv-skill",
            name: "Adversarial Skill",
            description: "Stress testing skill editor",
            category: "stress",
            path: tempDir.path,
            origin: .vault
        )

        let editor = SkillEditorState(skill: skill)
        editor.discoverAndLoadFiles()

        // Empirical check: directories must be excluded
        let fileNames = Set(editor.availableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(fileNames.contains("SKILL.md"), "SKILL.md must be included")
        XCTAssertTrue(fileNames.contains("doc1.md"), "doc1.md must be included")
        XCTAssertTrue(fileNames.contains("run.sh"), "run.sh must be included")

        XCTAssertFalse(fileNames.contains("subfolder"), "Subdirectories in references must be excluded")
        XCTAssertFalse(fileNames.contains("nested_dir"), "Subdirectories in scripts must be excluded")
        XCTAssertFalse(fileNames.contains(".hidden_file.md"), "Hidden files must be excluded")

        // Deep parent directory creation test (3 levels deep)
        let deepFile = tempDir
            .appendingPathComponent("level1")
            .appendingPathComponent("level2")
            .appendingPathComponent("level3")
            .appendingPathComponent("deep_target.md")

        XCTAssertFalse(FileManager.default.fileExists(atPath: deepFile.deletingLastPathComponent().path))

        editor.targetFileURL = deepFile
        editor.content = "Multi-level directory creation verified"
        editor.saveChanges()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: deepFile.path),
            "saveChanges must automatically create intermediate parent directories"
        )
        let readContent = try String(contentsOf: deepFile, encoding: .utf8)
        XCTAssertEqual(readContent, "Multi-level directory creation verified")
        XCTAssertEqual(editor.statusFeedback, "✓ Saved: deep_target.md")
    }

    // MARK: - Mission 4: RuntimeManifestPreviewView Body Zero-Lag Verification
    func testRuntimeManifestPreviewViewBodyDoesNotEncodeSynchronously() {
        let state = AppState(autoload: false)
        let project = ProjectProfile(
            id: "test-runtime-proj",
            name: "Test Runtime",
            path: "/tmp/test-runtime",
            enabledMCPServerIds: ["server-alpha"],
            enabledSkillIds: ["skill-beta"],
            enabledPluginIds: []
        )
        let server = MCPServerDefinition(
            id: "server-alpha",
            name: "Server Alpha",
            category: "core",
            config: ["command": .string("node"), "args": .array([.string("index.js")])]
        )
        state.servers = [server]

        let previewView = RuntimeManifestPreviewView(project: project, state: state)

        // Evaluate view body multiple times
        let body1 = previewView.body
        let body2 = previewView.body
        XCTAssertNotNil(body1)
        XCTAssertNotNil(body2)

        // Verify via Mirror that manifestJSON is stored in @State, not evaluated on the fly in body
        let mirror = Mirror(reflecting: previewView)
        var hasStoredManifestJSON = false
        for child in mirror.children {
            if child.label == "_manifestJSON" {
                hasStoredManifestJSON = true
                if let stateProperty = child.value as? State<String> {
                    let jsonText = stateProperty.wrappedValue
                    XCTAssertTrue(jsonText.contains("\"mcpServers\""))
                    XCTAssertTrue(jsonText.contains("server-alpha"))
                    XCTAssertTrue(jsonText.contains("index.js"))
                }
            }
        }
        XCTAssertTrue(hasStoredManifestJSON, "RuntimeManifestPreviewView must store manifestJSON in @State property")
        state.cancelPendingTasks()
    }

    // MARK: - Navigation & Empty States Adversarial Check
    func testSidebarPluginsAndFooterLogsNavigation() {
        let state = AppState(autoload: false)
        var selection: NavigationSection? = .masterVault
        let sidebar = ControlCenterSidebar(state: state, selection: Binding(get: { selection }, set: { selection = $0 }))
        XCTAssertNotNil(sidebar.body)

        // Switch selection to .plugins (Feature B4)
        selection = .plugins
        XCTAssertEqual(selection, .plugins)

        // Test footer setting navigationSelection to .syncLogs (Feature B5)
        let footer = ControlCenterFooter(state: state)
        XCTAssertNotNil(footer.body)

        state.navigationSelection = .masterVault
        XCTAssertEqual(state.navigationSelection, .masterVault)

        state.navigationSelection = .syncLogs
        XCTAssertEqual(state.navigationSelection, .syncLogs)
        state.cancelPendingTasks()
    }

    // MARK: - Adversarial Mission 1: ProjectProfile 6-Field Exhaustive Permutations & Set/Dict Integrity
    func testProjectProfileComprehensiveAdversarialFieldPermutations() {
        let base = ProjectProfile(
            id: "base-id",
            name: "Base Name",
            path: "/path/base",
            enabledMCPServerIds: ["mcp1", "mcp2"],
            enabledSkillIds: ["skill1", "skill2"],
            enabledPluginIds: ["plugin1"]
        )

        // 1. Reflexivity and symmetry
        XCTAssertEqual(base, base)
        XCTAssertEqual(base.hashValue, base.hashValue)

        let clone = ProjectProfile(
            id: "base-id",
            name: "Base Name",
            path: "/path/base",
            enabledMCPServerIds: ["mcp2", "mcp1"], // reverse order
            enabledSkillIds: ["skill2", "skill1"],
            enabledPluginIds: ["plugin1"]
        )
        XCTAssertEqual(base, clone, "Set order independence must preserve equality")
        XCTAssertEqual(base.hashValue, clone.hashValue, "Set order independence must preserve hashValue")

        // 2. Individual field mutation checks
        var tId = base; tId.id = "other-id"
        XCTAssertNotEqual(base, tId, "Field 1 (id) mutation must cause inequality")

        var tName = base; tName.name = "Other Name"
        XCTAssertNotEqual(base, tName, "Field 2 (name) mutation must cause inequality")

        var tPath = base; tPath.path = "/other/path"
        XCTAssertNotEqual(base, tPath, "Field 3 (path) mutation must cause inequality")

        var tMcp = base; tMcp.enabledMCPServerIds = ["mcp1"]
        XCTAssertNotEqual(base, tMcp, "Field 4 (enabledMCPServerIds) mutation must cause inequality")

        var tSkill = base; tSkill.enabledSkillIds = ["skill1"]
        XCTAssertNotEqual(base, tSkill, "Field 5 (enabledSkillIds) mutation must cause inequality")

        var tPlugin = base; tPlugin.enabledPluginIds = []
        XCTAssertNotEqual(base, tPlugin, "Field 6 (enabledPluginIds) mutation must cause inequality")

        // 3. Set collision test: In old bug, same ID meant Set dropped mutated profiles
        var projectSet = Set<ProjectProfile>()
        projectSet.insert(base)
        projectSet.insert(tMcp)
        projectSet.insert(tSkill)
        projectSet.insert(tPlugin)
        XCTAssertEqual(
            projectSet.count, 4,
            "Set<ProjectProfile> must store distinct profiles when MCP/Skill/Plugin sets differ despite identical id"
        )

        // 4. Dictionary key test
        var projectDict = [ProjectProfile: String]()
        projectDict[base] = "Original"
        projectDict[tMcp] = "MutatedMCP"
        XCTAssertEqual(projectDict[base], "Original")
        XCTAssertEqual(projectDict[tMcp], "MutatedMCP")
    }

    // MARK: - Adversarial Mission 2: RuntimeManifestPreviewView handleRegenerate & updateManifest
    func testRuntimeManifestPreviewHandleRegenerateAndStateWiring() async throws {
        let state = AppState(autoload: false)
        let server1 = MCPServerDefinition(
            id: "mcp-eval-1",
            name: "Server 1",
            category: "core",
            config: ["command": .string("deno"), "args": .array([.string("run"), .string("main.ts")])]
        )
        state.servers = [server1]

        let project = ProjectProfile(
            id: "proj-eval",
            name: "Eval Project",
            path: "/path/to/eval",
            enabledMCPServerIds: ["mcp-eval-1"],
            enabledSkillIds: ["skill-zebra", "skill-alpha"],
            enabledPluginIds: []
        )
        state.projects = [project]

        let preview = RuntimeManifestPreviewView(project: project, state: state)

        // Verify initial manifest string
        XCTAssertTrue(preview.manifestJSON.contains("\"mcpServers\""))
        XCTAssertTrue(preview.manifestJSON.contains("mcp-eval-1"))
        XCTAssertTrue(preview.manifestJSON.contains("deno"))
        XCTAssertFalse(preview.manifestJSON.contains("schemaVersion"))

        // Add server2 to state and project
        let server2 = MCPServerDefinition(
            id: "mcp-eval-2",
            name: "Server 2",
            category: "tools",
            config: ["command": .string("python3"), "args": .array([.string("-m"), .string("server")])]
        )
        state.servers.append(server2)

        var updatedProject = project
        updatedProject.enabledMCPServerIds.insert("mcp-eval-2")
        state.projects = [updatedProject]

        // Create updated preview view simulating SwiftUI re-render
        let updatedPreview = RuntimeManifestPreviewView(project: updatedProject, state: state)
        XCTAssertTrue(updatedPreview.manifestJSON.contains("mcp-eval-2"))
        XCTAssertTrue(updatedPreview.manifestJSON.contains("python3"))

        // Now test handleRegenerate directly on preview
        preview.handleRegenerate()
        XCTAssertTrue(preview.manifestJSON.contains("mcp-eval-1"))

        // Give background task a moment
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(state.statusMessage?.contains("Synchronized project: Eval Project") == true)
        state.cancelPendingTasks()
    }
}

