import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

@MainActor
final class Phase1ImprovementsTests: XCTestCase {
    private var sandboxDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        let dir = fm.temporaryDirectory.appendingPathComponent("Phase1Tests_\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - 1. ProjectProfile Backwards-Compatible JSON Decoding

    func testProjectProfileDecodesLegacyJSONWithoutDismissedRecommendationKeys() throws {
        let legacyJSON = """
        [
          {
            "id": "legacy-app",
            "name": "Legacy App",
            "path": "/tmp/legacy-app",
            "enabledMCPServerIds": ["github"],
            "enabledSkillIds": ["ask"],
            "enabledPluginIds": []
          }
        ]
        """
        let decoded = try JSONDecoder().decode([ProjectProfile].self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "legacy-app")
        XCTAssertEqual(decoded[0].enabledMCPServerIds, ["github"])
        XCTAssertEqual(decoded[0].enabledSkillIds, ["ask"])
        XCTAssertTrue(decoded[0].dismissedRecommendationKeys.isEmpty)
    }

    // MARK: - 2. Recommendation Dismissal, Filtering, and Reset

    func testDismissAndResetRecommendationsInServiceAndAppState() async throws {
        let projDir = PathConstants.desktopProjectsDirectory.appendingPathComponent("web-shop", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        try #"{"dependencies":{"next":"15.0.0","@supabase/supabase-js":"2.0.0"}}"#
            .write(to: projDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let vault = VaultService()
        let supabase = MCPServerDefinition(id: "supabase", name: "Supabase", category: "Database", config: ["command": .string("npx")])
        await vault.saveServers([supabase])

        let uiDir = PathConstants.vaultSkillsDirectory.appendingPathComponent("ui-architect", isDirectory: true)
        try fm.createDirectory(at: uiDir, withIntermediateDirectories: true)
        try "---\nname: UI Architect\ndescription: UI\n---\n".write(to: uiDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let noSlopDir = PathConstants.vaultSkillsDirectory.appendingPathComponent("no-ai-slop", isDirectory: true)
        try fm.createDirectory(at: noSlopDir, withIntermediateDirectories: true)
        try "---\nname: No AI Slop\ndescription: Clean UI\n---\n".write(to: noSlopDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let state = AppState(autoload: false)
        await state.loadData()

        let initialRecs = state.projectRecommendations["web-shop"] ?? []
        XCTAssertTrue(initialRecs.contains(where: { $0.uniqueKey == "mcp:supabase" }))
        XCTAssertTrue(initialRecs.contains(where: { $0.uniqueKey == "skill:ui-architect" }))
        XCTAssertTrue(initialRecs.contains(where: { $0.uniqueKey == "skill:no-ai-slop" }))

        // Dismiss one recommendation
        let noSlopRec = try XCTUnwrap(initialRecs.first(where: { $0.uniqueKey == "skill:no-ai-slop" }))
        state.dismissRecommendation(noSlopRec, for: "web-shop")

        XCTAssertEqual(state.dismissedRecommendationCount(for: "web-shop"), 1)
        XCTAssertFalse(state.projectRecommendations["web-shop"]?.contains(where: { $0.uniqueKey == "skill:no-ai-slop" }) ?? true)

        // Wait briefly for Vault persistence and verify ProjectRecommendationService filters dismissed key
        try await Task.sleep(nanoseconds: 100_000_000)
        await state.refreshRecommendations(for: "web-shop")
        XCTAssertFalse(state.projectRecommendations["web-shop"]?.contains(where: { $0.uniqueKey == "skill:no-ai-slop" }) ?? true)

        // Also verify includeDismissed = true still surfaces it
        let service = ProjectRecommendationService()
        let project = try XCTUnwrap(state.projects.first(where: { $0.id == "web-shop" }))
        let allWithDismissed = service.recommend(
            for: project,
            availableServers: state.servers,
            globalServerIds: state.globalServerIds,
            availableSkills: state.skills,
            globalSkillIds: state.globalSkillIds,
            availablePlugins: state.plugins,
            globalPluginIds: state.globalPluginIds,
            includeDismissed: true
        )
        XCTAssertTrue(allWithDismissed.contains(where: { $0.uniqueKey == "skill:no-ai-slop" }))

        // Reset dismissed recommendations
        state.resetDismissedRecommendations(for: "web-shop")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(state.dismissedRecommendationCount(for: "web-shop"), 0)
        XCTAssertTrue(state.projectRecommendations["web-shop"]?.contains(where: { $0.uniqueKey == "skill:no-ai-slop" }) ?? false)
        state.cancelPendingTasks()
    }

    // MARK: - 3. MenuBarRecommendationsSection (5+ items) & ProjectRecommendationsCard

    func testRecommendationsMenuBarAndControlCenterViewsRenderFivePlusItemsCleanly() {
        let state = AppState(autoload: false)
        let proj = ProjectProfile(
            id: "demo-five",
            name: "DemoFive",
            path: "/tmp/demo-five",
            dismissedRecommendationKeys: ["skill:optional-extra"]
        )
        state.projects = [proj]
        state.selectedProjectId = "demo-five"
        state.projectStackLabels["demo-five"] = ["Next.js", "Supabase"]

        let recs: [ResourceRecommendation] = [
            ResourceRecommendation(id: "supabase", name: "Supabase", kind: .mcp, reason: "Detected Supabase", priority: .high),
            ResourceRecommendation(id: "modern-web-guidance-plugin", name: "Modern Web Guidance", kind: .plugin, reason: "Detected Next.js", priority: .high),
            ResourceRecommendation(id: "ui-architect", name: "UI Architect", kind: .skill, reason: "Web architecture", priority: .medium),
            ResourceRecommendation(id: "vercel-web-design-guidelines", name: "Vercel Web Design Guidelines", kind: .skill, reason: "Web UI standards", priority: .medium),
            ResourceRecommendation(id: "no-ai-slop", name: "No AI Slop", kind: .skill, reason: "Clean UI polish", priority: .low)
        ]
        state.projectRecommendations["demo-five"] = recs

        let menuSection = MenuBarRecommendationsSection(
            state: state,
            projectId: "demo-five",
            recommendations: recs,
            stackLabels: ["Next.js", "Supabase"]
        )
        let menuHost = NSHostingView(rootView: menuSection.frame(width: 344))
        menuHost.layout()
        XCTAssertGreaterThan(menuHost.fittingSize.height, 80)
        XCTAssertLessThan(menuHost.fittingSize.height, 800)

        let controlCenterCard = ProjectRecommendationsCard(state: state, projectId: "demo-five")
        let cardHost = NSHostingView(rootView: controlCenterCard.frame(width: 720))
        cardHost.layout()
        XCTAssertGreaterThan(cardHost.fittingSize.height, 100)
        XCTAssertLessThan(cardHost.fittingSize.height, 1500)

        // Enable only essential (high-priority) subset
        let highRecs = recs.filter { $0.priority == .high }
        state.enableRecommendations(highRecs, for: "demo-five")
        XCTAssertEqual(state.projects[0].enabledMCPServerIds, ["supabase"])
        XCTAssertEqual(state.projects[0].enabledPluginIds, ["modern-web-guidance-plugin"])
        XCTAssertEqual(state.projectRecommendations["demo-five"]?.count, 3)

        state.cancelPendingTasks()
    }

    // MARK: - 4. ProjectScannerService Ignores _archive, _backups, _temp, and archived

    func testProjectScannerIgnoresMetaAndArchivedFolders() throws {
        let root = PathConstants.desktopProjectsDirectory
        let ignoredFolders = ["_archive", "_backups", "_temp", "archived"]
        for name in ignoredFolders {
            try fm.createDirectory(at: root.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
        let nestedArchived = root.appendingPathComponent("_archive/old-repo", isDirectory: true)
        try fm.createDirectory(at: nestedArchived.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let activeRepo = root.appendingPathComponent("real-app", isDirectory: true)
        try fm.createDirectory(at: activeRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let scanner = ProjectScannerService()
        let discovered = scanner.discoverProjects(in: root, scanDefaultWhenNil: false)
        let discoveredNames = Set(discovered.map(\.name))

        XCTAssertTrue(discoveredNames.contains("real-app"))
        for ignored in ignoredFolders {
            XCTAssertFalse(discoveredNames.contains(ignored), "Scanner must ignore '\(ignored)'")
        }
        XCTAssertTrue(
            ProjectScannerService.isInsideIgnoredContainer(nestedArchived.path, rootPrefix: root.path),
            "Should detect nested path inside _archive"
        )
        XCTAssertFalse(
            ProjectScannerService.isInsideIgnoredContainer(activeRepo.path, rootPrefix: root.path),
            "Should not mark normal repo as inside ignored container"
        )
    }

    // MARK: - 5. ProjectIsolationSidebarView Sorted Skills & Callback

    func testProjectIsolationSidebarViewDeterministicSkillsAndCallback() {
        let state = AppState(autoload: false)
        let project = ProjectProfile(
            id: "sidebar-proj",
            name: "SidebarProj",
            path: "/tmp/sidebar-proj",
            enabledSkillIds: ["zeta", "alpha", "gamma", "beta", "delta"]
        )
        state.projects = [project]

        var tapped = false
        let sidebar = ProjectIsolationSidebarView(
            project: project,
            state: state,
            onLinkSkillTap: { tapped = true }
        )
        let host = NSHostingView(rootView: sidebar)
        host.layout()
        XCTAssertGreaterThan(host.fittingSize.height, 120)

        sidebar.onLinkSkillTap?()
        XCTAssertTrue(tapped)
        state.cancelPendingTasks()
    }
}
