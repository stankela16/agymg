import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

@MainActor
final class MenuBarAndRedesignTests: XCTestCase {
    private var sandboxDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("MenuBarRedesign_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        sandboxDir = dir

        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.pathKey)
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: ProjectFolderAccessManager.pathKey)
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let sandboxDir {
            try? fm.removeItem(at: sandboxDir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        try await super.tearDown()
    }

    func testArchiveContainerFilteringPrunesNestedArchivedProjects() async throws {
        let projectsRoot = sandboxDir.appendingPathComponent("Projects", isDirectory: true)
        let archivedRepo = projectsRoot.appendingPathComponent("_archive/99c.bot", isDirectory: true)
        let deepArchived = projectsRoot.appendingPathComponent("_archive/nested/old-bot", isDirectory: true)
        let activeRepo = projectsRoot.appendingPathComponent("active-app", isDirectory: true)

        try fm.createDirectory(at: archivedRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: deepArchived.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: activeRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        XCTAssertTrue(ProjectScannerService.isInsideIgnoredContainer(archivedRepo.path))
        XCTAssertTrue(ProjectScannerService.isInsideIgnoredContainer(deepArchived.path))
        XCTAssertFalse(ProjectScannerService.isInsideIgnoredContainer(activeRepo.path, rootPrefix: projectsRoot.path))

        ProjectFolderAccessManager.shared.saveAuthorization(url: projectsRoot)

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()
        await vault.saveProjects([
            ProjectProfile(id: "_archive/99c.bot", name: "_archive/99c.bot", path: archivedRepo.path),
            ProjectProfile(id: "old-bot", name: "old-bot", path: deepArchived.path),
            ProjectProfile(id: "active-app", name: "active-app", path: activeRepo.path)
        ])

        let loaded = await vault.loadProjects()
        XCTAssertEqual(loaded.map(\.name), ["active-app"])

        let savedWithoutTCC = await vault.loadSavedProjectsWithoutTCC()
        XCTAssertEqual(savedWithoutTCC.map(\.name), ["active-app"])
    }

    func testExtractSkillPreviewAndOffMainLoading() async throws {
        let skillDir = sandboxDir.appendingPathComponent("skills/sample-skill", isDirectory: true)
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let markdown = """
        ---
        name: sample-skill
        description: Sample frontmatter description
        ---

        # Sample Skill

        Guides onboarding optimization with concrete checklist patterns.

        ## When to Use
        - Reviewing sign-up and paywall flows
        """
        try markdown.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let parsed = AppState.extractSkillPreview(from: markdown)
        XCTAssertFalse(parsed.contains("---"))
        XCTAssertFalse(parsed.contains("Sample Skill"))
        XCTAssertTrue(parsed.contains("Guides onboarding optimization"))
        XCTAssertTrue(parsed.contains("When to Use:"))

        let state = AppState(autoload: false)
        let skill = SkillDefinition(
            id: "sample-skill",
            name: "Sample Skill",
            description: "Sample frontmatter description",
            path: skillDir.path,
            origin: .vault
        )
        state.skills = [skill]
        state.loadSkillPreviewIfNeeded(for: skill)

        for _ in 0..<40 {
            if state.skillPreviews[skill.id] != nil { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let loadedPreview = state.skillPreviews[skill.id]
        XCTAssertNotNil(loadedPreview)
        XCTAssertTrue(loadedPreview?.contains("Guides onboarding optimization") == true)
        state.cancelPendingTasks()
    }

    func testPopoverFeedbackImmediateForSkillsAndReloadForMCP() {
        let state = AppState(autoload: false)
        let project = ProjectProfile(id: "demo", name: "Demo", path: sandboxDir.path)
        state.projects = [project]
        state.skills = [SkillDefinition(id: "ui-architect", name: "UI Architect", description: "UI", path: "/tmp/ui")]
        state.servers = [MCPServerDefinition(id: "github", name: "GitHub", config: ["command": .string("npx")])]

        state.toggleProjectSkill(projectId: project.id, skillId: "ui-architect")
        XCTAssertEqual(state.popoverFeedback?.requiresChatReload, false)
        XCTAssertTrue(state.popoverFeedback?.detail.localizedCaseInsensitiveContains("immediately") == true)

        state.toggleProjectServer(projectId: project.id, serverId: "github")
        XCTAssertEqual(state.popoverFeedback?.requiresChatReload, true)
        XCTAssertTrue(state.popoverFeedback?.detail.localizedCaseInsensitiveContains("new chat") == true)

        let skillRec = ResourceRecommendation(id: "ui-architect", name: "UI Architect", kind: .skill, reason: "Web UI")
        let mcpRec = ResourceRecommendation(id: "supabase", name: "Supabase", kind: .mcp, reason: "DB")
        state.enableRecommendations([skillRec], for: project.id)
        XCTAssertEqual(state.popoverFeedback?.requiresChatReload, false)

        state.enableRecommendations([skillRec, mcpRec], for: project.id)
        XCTAssertEqual(state.popoverFeedback?.requiresChatReload, true)

        state.dismissPopoverFeedback()
        XCTAssertNil(state.popoverFeedback)
        state.cancelPendingTasks()
    }

    func testMenuBarPopoverPreservesWidthHeightWithRecommendationsAndPreviews() {
        let state = AppState(autoload: false)
        let project = ProjectProfile(id: "ios-app", name: "eho-ios", path: sandboxDir.path)
        let skill = SkillDefinition(
            id: "apple-onboarding-cro",
            name: "Apple Onboarding Cro",
            description: "Optimize iOS onboarding, paywalls, and first-run conversion flows.",
            category: "Swift & Apple",
            path: "/tmp/apple-onboarding-cro",
            origin: .vault
        )
        state.projects = [project]
        state.selectedProjectId = project.id
        state.activeWorkspaceSource = "xcode"
        state.skills = [skill]
        state.servers = (0..<6).map { idx in
            MCPServerDefinition(id: "srv-\(idx)", name: "Server \(idx)", config: ["command": .string("npx srv-\(idx)")])
        }
        state.skillPreviews[skill.id] = "Guides iOS onboarding structure, permission priming, and conversion checkpoints."
        state.projectStackLabels[project.id] = ["Xcode / iOS"]
        state.projectRecommendations[project.id] = [
            ResourceRecommendation(
                id: "apple-onboarding-cro",
                name: "Apple Onboarding Cro",
                kind: .skill,
                reason: "Detected iOS project — App Store & onboarding flow optimization",
                priority: .high
            )
        ]
        state.showPopoverFeedback(
            message: "Synced · Apple Onboarding Cro enabled",
            detail: "Active immediately — no chat restart needed",
            requiresChatReload: false
        )

        let host = NSHostingView(rootView: MenuBarPopoverView(state: state))
        host.layout()
        let size = host.fittingSize

        XCTAssertEqual(size.width, DesignTokens.Dimensions.popoverWidth, accuracy: 2.0)
        XCTAssertGreaterThanOrEqual(size.height, 420.0)
        state.cancelPendingTasks()
    }

    func testMCPServerDefinitionEndpointHelpersAndWrappingLayout() {
        let remote = MCPServerDefinition(
            id: "mobbin",
            name: "mobbin",
            config: ["serverUrl": .string("https://api.mobbin.com/mcp")]
        )
        XCTAssertEqual(remote.transportLabel, "Remote HTTP")
        XCTAssertEqual(remote.displayEndpoint, "https://api.mobbin.com/mcp")

        let homeScript = PathConstants.homeDirectory.appendingPathComponent(".local/share/akmanos-mcp/index.js").path
        let stdio = MCPServerDefinition(
            id: "akmanos",
            name: "akmanos",
            config: [
                "command": .string("/opt/homebrew/bin/node"),
                "args": .array([.string(homeScript)])
            ]
        )
        XCTAssertEqual(stdio.transportLabel, "Local stdio")
        XCTAssertEqual(stdio.displayEndpoint, "/opt/homebrew/bin/node ~/.local/share/akmanos-mcp/index.js")

        let badgesView = WrappingHStackLayout {
            ResourcePillBadge.category("Tools")
            ResourcePillBadge.global
            ResourcePillBadge.scopedProjects(3)
        }
        .frame(width: 180)
        let host = NSHostingView(rootView: badgesView)
        host.layout()
        XCTAssertGreaterThan(host.fittingSize.height, 24)
    }

    func testControlCenterRendersWithInspectorAndFooterWithoutCrash() {
        let state = AppState(autoload: false)
        state.isProjectsFolderAuthorized = true
        state.servers = [
            MCPServerDefinition(id: "github", name: "GitHub", config: ["command": .string("npx github")])
        ]
        state.skills = [
            SkillDefinition(id: "find-skills", name: "Find Skills", description: "Discover community skills", path: "/tmp/find-skills")
        ]
        let proj = ProjectProfile(id: "app", name: "App", path: sandboxDir.path)
        state.projects = [proj]

        let ccHost = NSHostingView(rootView: ControlCenterView(state: state).frame(width: 1200, height: 760))
        ccHost.layout()
        XCTAssertGreaterThan(ccHost.fittingSize.width, 0)
        XCTAssertGreaterThan(ccHost.fittingSize.height, 0)

        let footerHost = NSHostingView(rootView: VaultEngineFooterView(state: state).frame(width: 240))
        footerHost.layout()
        XCTAssertGreaterThan(footerHost.fittingSize.height, 40)
        state.cancelPendingTasks()
    }

    func testCLISessionStartRadarIncludesFindSkillsGuidance() async throws {
        let projDir = sandboxDir.appendingPathComponent("Projects/sample-repo", isDirectory: true)
        try fm.createDirectory(at: projDir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()

        let result = await CLIRunner.execute(
            arguments: ["agymg", "hook-session-start", "--format", "claude-text", "--project", projDir.path],
            currentDirectoryPath: projDir.path
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("find-skills"))
        XCTAssertTrue(result.stdout.contains("agymg import-skill"))
    }
}
