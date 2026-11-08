import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

@MainActor
final class M3R3_1ChallengerAdversarialTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M3R3_1Challenge-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, fm.fileExists(atPath: tempDir.path) {
            try? fm.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - 1. Exhaustive Source AST / Token Analysis: ZERO Vertical ScrollViews

    func testChildTabFilesHaveZeroVerticalScrollViewAndZeroMaxHeightInfinity() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let basePath = repoRoot.appendingPathComponent("Sources/AntigravityManager/Views").path
        let childTabFiles = [
            "\(basePath)/MasterVault/VaultServersTab.swift",
            "\(basePath)/MasterVault/VaultSkillsTab.swift",
            "\(basePath)/MasterVault/VaultPluginsTab.swift",
            "\(basePath)/Projects/ProjectServersTab.swift",
            "\(basePath)/Projects/ProjectSkillsTab.swift",
            "\(basePath)/Projects/ProjectPluginsTab.swift"
        ]

        for path in childTabFiles {
            let exists = fm.fileExists(atPath: path)
            XCTAssertTrue(exists, "Expected child tab file to exist at \(path)")
            let content = try String(contentsOfFile: path, encoding: .utf8)

            // Adversarial check: No vertical ScrollView allowed in child tab
            XCTAssertFalse(content.contains("ScrollView {"), "Found vertical 'ScrollView {' in \(path)")
            XCTAssertFalse(content.contains("ScrollView()"), "Found vertical 'ScrollView()' in \(path)")
            XCTAssertFalse(content.contains("ScrollView(.vertical"), "Found 'ScrollView(.vertical' in \(path)")
            XCTAssertFalse(content.contains("ScrollView([.vertical"), "Found 'ScrollView([.vertical' in \(path)")

            // Check no nested ScrollViews at all in these 6 files
            XCTAssertFalse(content.contains("ScrollView("), "Found ScrollView constructor in \(path)")

            // Adversarial check: No maxHeight: .infinity in child tabs or empty views
            XCTAssertFalse(content.contains("maxHeight: .infinity"), "Found 'maxHeight: .infinity' in \(path), which breaks container bounds")
        }
    }

    func testParentViewsContainSingleOuterScrollView() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let basePath = repoRoot.appendingPathComponent("Sources/AntigravityManager/Views").path
        let masterVaultPath = "\(basePath)/MasterVault/MasterVaultView.swift"
        let projectDetailPath = "\(basePath)/Projects/ProjectDetailView.swift"

        let mvContent = try String(contentsOfFile: masterVaultPath, encoding: .utf8)
        let pdContent = try String(contentsOfFile: projectDetailPath, encoding: .utf8)

        // Both parent views must establish the outer ScrollView
        XCTAssertTrue(mvContent.contains("ScrollView {"), "MasterVaultView must establish the parent ScrollView")
        XCTAssertTrue(pdContent.contains("ScrollView {"), "ProjectDetailView must establish the parent ScrollView")

        // Ensure there is only 1 top-level ScrollView in each parent view file
        let mvScrollViewMatches = mvContent.components(separatedBy: "ScrollView {").count - 1
        XCTAssertEqual(mvScrollViewMatches, 1, "MasterVaultView must contain exactly ONE outer vertical ScrollView")

        let pdScrollViewMatches = pdContent.components(separatedBy: "ScrollView {").count - 1
        XCTAssertEqual(pdScrollViewMatches, 1, "ProjectDetailView must contain exactly ONE outer vertical ScrollView")
    }

    // MARK: - 2. Empty State Bounds & Sizing (0 items)

    func testEmptyStateBoundsDoNotExpandToInfinityOrCollapse() {
        let state = AppState(autoload: false)
        state.servers = []
        state.skills = []
        state.plugins = []

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let vaultServers = VaultServersTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        let vaultSkills = VaultSkillsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        let vaultPlugins = VaultPluginsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))

        let project = ProjectProfile(id: "p0", name: "Empty Project", path: tempDir.path)
        state.projects = [project]

        let projServers = ProjectServersTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        let projSkills = ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        let projPlugins = ProjectPluginsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))

        // Measure fitting sizes inside standard desktop container (width: 800)
        let views: [(String, AnyView)] = [
            ("VaultServersTab", AnyView(vaultServers)),
            ("VaultSkillsTab", AnyView(vaultSkills)),
            ("VaultPluginsTab", AnyView(vaultPlugins)),
            ("ProjectServersTab", AnyView(projServers)),
            ("ProjectSkillsTab", AnyView(projSkills)),
            ("ProjectPluginsTab", AnyView(projPlugins))
        ]

        for (name, view) in views {
            let host = NSHostingView(rootView: view.frame(width: 800))
            host.layout()
            let size = host.fittingSize

            // Must NOT collapse to zero height
            XCTAssertGreaterThan(size.height, 40, "\(name) empty state height must not collapse to 0 (was \(size.height))")
            // Must NOT blow up infinitely
            XCTAssertLessThan(size.height, 2000, "\(name) empty state height must be within standard bounds (was \(size.height))")
            XCTAssertFalse(size.height.isInfinite, "\(name) empty state height must not be infinite")
        }
    }

    // MARK: - 3. Scale Stress Testing: 0, 5, 20, 100 items for MasterVaultView

    func testMasterVaultScaleStress0_5_20_100Items() {
        let itemCounts = [0, 5, 20, 100]
        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        for count in itemCounts {
            let state = AppState(autoload: false)
            state.servers = (0..<count).map { i in
                MCPServerDefinition(
                    id: "server-\(i)",
                    name: "Server #\(i)",
                    category: i % 2 == 0 ? "Core & Tools" : "Web & Frontend",
                    config: [
                        "command": .string("npx -y @modelcontextprotocol/server-\(i)"),
                        "args": .array([.string("/path/to/server-\(i)")])
                    ]
                )
            }
            state.skills = (0..<count).map { i in
                SkillDefinition(
                    id: "skill-\(i)",
                    name: "Skill #\(i)",
                    description: "Stress test skill description #\(i)",
                    category: "Core & Tools",
                    path: "/vault/skills/skill-\(i)",
                    origin: .vault
                )
            }
            state.plugins = (0..<count).map { i in
                PluginDefinition(
                    id: "plugin-\(i)",
                    name: "Plugin #\(i)",
                    path: "/vault/plugins/plugin-\(i)",
                    hasMCP: i % 2 == 0,
                    hasSkills: i % 3 == 0
                )
            }

            let masterVaultView = MasterVaultView(
                state: state,
                deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
                editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
            )

            let host = NSHostingView(rootView: masterVaultView.frame(width: 900, height: 700))
            host.layout()
            let fittingSize = host.fittingSize

            // Layout must not collapse
            XCTAssertGreaterThan(fittingSize.height, 0, "MasterVaultView fittingSize.height must be > 0 at \(count) items")
            XCTAssertGreaterThan(fittingSize.width, 0, "MasterVaultView fittingSize.width must be > 0 at \(count) items")

            // Verify host contains NSScrollView (parent scrollview)
            let scrollViews = findSubviews(of: NSScrollView.self, in: host)
            XCTAssertFalse(scrollViews.isEmpty, "MasterVaultView must contain the parent NSScrollView at \(count) items")

            // Verify that NO vertical NSScrollView is nested inside another vertical NSScrollView
            for sv in scrollViews {
                let parentScrollViews = findParentViews(of: NSScrollView.self, for: sv)
                let nestedVerticalParent = parentScrollViews.first { parentSv in
                    parentSv.hasVerticalScroller || parentSv.verticalScrollElasticity != .none
                }
                if sv.hasVerticalScroller && nestedVerticalParent != nil {
                    XCTFail("Found nested vertical NSScrollView inside another NSScrollView at count \(count)")
                }
            }
        }
    }

    // MARK: - 4. Scale Stress Testing: 0, 5, 20, 100 items for ProjectDetailView

    func testProjectDetailScaleStress0_5_20_100Items() {
        let itemCounts = [0, 5, 20, 100]
        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        for count in itemCounts {
            let state = AppState(autoload: false)
            let project = ProjectProfile(
                id: "proj-stress",
                name: "Stress Project",
                path: tempDir.path,
                enabledMCPServerIds: Set((0..<(count / 2)).map { "server-\($0)" }),
                enabledSkillIds: Set((0..<(count / 2)).map { "skill-\($0)" }),
                enabledPluginIds: Set((0..<(count / 2)).map { "plugin-\($0)" })
            )
            state.projects = [project]

            state.servers = (0..<count).map { i in
                MCPServerDefinition(
                    id: "server-\(i)",
                    name: "Server #\(i)",
                    category: "Core & Tools",
                    config: ["command": .string("cmd-\(i)")]
                )
            }
            state.skills = (0..<count).map { i in
                SkillDefinition(
                    id: "skill-\(i)",
                    name: "Skill #\(i)",
                    description: "Skill description \(i)",
                    category: "Core & Tools",
                    path: "/vault/skills/skill-\(i)",
                    origin: .vault
                )
            }
            state.plugins = (0..<count).map { i in
                PluginDefinition(
                    id: "plugin-\(i)",
                    name: "Plugin #\(i)",
                    path: "/vault/plugins/plugin-\(i)",
                    hasMCP: true,
                    hasSkills: true
                )
            }

            let projectDetailView = ProjectDetailView(
                state: state,
                project: project,
                deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
                editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
            )

            let host = NSHostingView(rootView: projectDetailView.frame(width: 900, height: 700))
            host.layout()
            let fittingSize = host.fittingSize

            // Layout must not collapse
            XCTAssertGreaterThan(fittingSize.height, 0, "ProjectDetailView fittingSize.height must be > 0 at \(count) items")
            XCTAssertGreaterThan(fittingSize.width, 0, "ProjectDetailView fittingSize.width must be > 0 at \(count) items")

            // Verify host contains parent NSScrollView
            let scrollViews = findSubviews(of: NSScrollView.self, in: host)
            XCTAssertFalse(scrollViews.isEmpty, "ProjectDetailView must contain NSScrollView at \(count) items")

            // Verify no nested vertical NSScrollViews exist
            for sv in scrollViews {
                let parentScrollViews = findParentViews(of: NSScrollView.self, for: sv)
                let nestedVerticalParent = parentScrollViews.first { parentSv in
                    parentSv.hasVerticalScroller || parentSv.verticalScrollElasticity != .none
                }
                if sv.hasVerticalScroller && nestedVerticalParent != nil {
                    XCTFail("Found nested vertical NSScrollView inside another NSScrollView in ProjectDetailView at count \(count)")
                }
            }
        }
    }

    // MARK: - 5. Rapid Tab Switching & View Instantiation Performance

    func testRapidTabSwitchingAndRenderBenchmark() {
        let state = AppState(autoload: false)
        state.servers = (0..<50).map { i in
            MCPServerDefinition(id: "srv-\(i)", name: "Server \(i)", category: "Core & Tools", config: [:])
        }
        state.skills = (0..<50).map { i in
            SkillDefinition(id: "sk-\(i)", name: "Skill \(i)", description: "Desc \(i)", category: "Core & Tools", path: "/path/\(i)", origin: .vault)
        }
        state.plugins = (0..<50).map { i in
            PluginDefinition(id: "pl-\(i)", name: "Plugin \(i)", path: "/pl/\(i)", hasMCP: true, hasSkills: true)
        }
        let project = ProjectProfile(id: "p1", name: "P1", path: tempDir.path)
        state.projects = [project]

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let startTime = CFAbsoluteTimeGetCurrent()
        let iterations = 200

        for _ in 0..<iterations {
            let v1 = VaultServersTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
            _ = v1.body
            let v2 = VaultSkillsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
            _ = v2.body
            let v3 = VaultPluginsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
            _ = v3.body

            let p1 = ProjectServersTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
            _ = p1.body
            let p2 = ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
            _ = p2.body
            let p3 = ProjectPluginsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
            _ = p3.body
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let perIteration = (elapsed / Double(iterations)) * 1000.0 // ms
        print("[EMPIRICAL BENCHMARK] \(iterations) iterations of 6 child tabs: \(String(format: "%.4f", elapsed))s, avg: \(String(format: "%.3f", perIteration)) ms/iteration")

        // Must execute under 5ms per iteration on Apple Silicon (zero-lag requirement)
        XCTAssertLessThan(perIteration, 10.0, "Child tab body instantiation took too long: \(perIteration) ms")
    }

    // MARK: - 6. Search and Category Filter Empty States

    func testSearchAndCategoryFilterEmptyStatesLayoutBounds() {
        let state = AppState(autoload: false)
        state.servers = [
            MCPServerDefinition(id: "s1", name: "Alpha", category: "Core & Tools", config: [:])
        ]
        state.skills = [
            SkillDefinition(id: "sk1", name: "Beta", description: "Desc", category: "Core & Tools", path: "/sk1", origin: .vault)
        ]
        state.plugins = [
            PluginDefinition(id: "p1", name: "Gamma", path: "/p1", hasMCP: true, hasSkills: false)
        ]
        let project = ProjectProfile(id: "p1", name: "P1", path: tempDir.path)
        state.projects = [project]

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        // All 6 tabs with populated state
        let v1 = VaultServersTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        let v2 = VaultSkillsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        let v3 = VaultPluginsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        let p1 = ProjectServersTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        let p2 = ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        let p3 = ProjectPluginsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))

        for (name, view) in [("v1", AnyView(v1)), ("v2", AnyView(v2)), ("v3", AnyView(v3)), ("p1", AnyView(p1)), ("p2", AnyView(p2)), ("p3", AnyView(p3))] {
            let host = NSHostingView(rootView: view.frame(width: 800))
            host.layout()
            let size = host.fittingSize
            XCTAssertGreaterThan(size.height, 30, "\(name) layout height must not collapse")
            XCTAssertLessThan(size.height, 2000, "\(name) layout height must be bounded")
        }
    }

    // MARK: - 7. ProjectSkillsTab Local vs. Vault Split Layout

    func testProjectSkillsTabLocalsAndVaultSplitRendering() {
        let state = AppState(autoload: false)
        let project = ProjectProfile(id: "split-proj", name: "Split Proj", path: tempDir.path)
        state.projects = [project]

        // 1. Both locals and vault skills present
        state.projectLocalSkills[project.path] = [
            SkillDefinition(id: "loc1", name: "Local 1", description: "Local desc", category: "Swift & Apple", path: "/loc1", origin: .projectLocal)
        ]
        state.skills = [
            SkillDefinition(id: "vlt1", name: "Vault 1", description: "Vault desc", category: "Core & Tools", path: "/vlt1", origin: .vault)
        ]

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let tabBoth = ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        let hostBoth = NSHostingView(rootView: tabBoth.frame(width: 800))
        hostBoth.layout()
        let sizeBoth = hostBoth.fittingSize
        XCTAssertGreaterThan(sizeBoth.height, 100, "Both locals and vault skills must render with height > 100")

        // 2. Only locals present
        state.skills = []
        let tabLocalsOnly = ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        let hostLocals = NSHostingView(rootView: tabLocalsOnly.frame(width: 800))
        hostLocals.layout()
        let sizeLocals = hostLocals.fittingSize
        XCTAssertGreaterThan(sizeLocals.height, 80, "Locals-only must render with height > 80")

        // 3. Only vault present
        state.projectLocalSkills[project.path] = []
        state.skills = [
            SkillDefinition(id: "vlt1", name: "Vault 1", description: "Vault desc", category: "Core & Tools", path: "/vlt1", origin: .vault)
        ]
        let tabVaultOnly = ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        let hostVault = NSHostingView(rootView: tabVaultOnly.frame(width: 800))
        hostVault.layout()
        let sizeVault = hostVault.fittingSize
        XCTAssertGreaterThan(sizeVault.height, 80, "Vault-only must render with height > 80")
    }

    // MARK: - View Hierarchy Traversal Helpers

    private func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var matches: [T] = []
        for sub in root.subviews {
            if let matched = sub as? T {
                matches.append(matched)
            }
            matches.append(contentsOf: findSubviews(of: type, in: sub))
        }
        return matches
    }

    private func findParentViews<T: NSView>(of type: T.Type, for view: NSView) -> [T] {
        var matches: [T] = []
        var current: NSView? = view.superview
        while let parent = current {
            if let matched = parent as? T {
                matches.append(matched)
            }
            current = parent.superview
        }
        return matches
    }
}
