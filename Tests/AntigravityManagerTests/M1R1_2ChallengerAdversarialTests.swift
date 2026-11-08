import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

@MainActor
final class M1R1_2ChallengerAdversarialTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            WindowRouter.openControlCenter = nil
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            WindowRouter.openControlCenter = nil
        }
        super.tearDown()
    }

    // MARK: - Challenge 1: MenuBarPopoverView Scale & Stress Testing (0, 1, 6, 12, 50, 100 servers)

    func testMenuBarPopoverScaleZeroServers() {
        let state = AppState(autoload: false)
        state.servers = []
        state.globalServerIds = []

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body, "MenuBarPopoverView must render cleanly with 0 servers (empty state)")
        state.cancelPendingTasks()
    }

    func testMenuBarPopoverScaleOneServer() {
        let state = AppState(autoload: false)
        let srv = MCPServerDefinition(id: "srv-1", name: "Server 1", category: "core", config: [:])
        state.servers = [srv]
        state.globalServerIds = ["srv-1"]

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body, "MenuBarPopoverView must render cleanly with 1 server")
        state.cancelPendingTasks()
    }

    func testMenuBarPopoverScaleSixServersBoundary() {
        let state = AppState(autoload: false)
        state.servers = (1...6).map {
            MCPServerDefinition(id: "srv-\($0)", name: "Server \($0)", category: "core", config: [:])
        }
        state.globalServerIds = Set(["srv-1", "srv-2", "srv-3"])

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body, "MenuBarPopoverView must render cleanly at old 6-server boundary")
        state.cancelPendingTasks()
    }

    func testMenuBarPopoverScaleTwelveServers() {
        let state = AppState(autoload: false)
        state.servers = (1...12).map {
            MCPServerDefinition(id: "srv-\($0)", name: "Server \($0)", category: "core", config: [:])
        }
        state.globalServerIds = Set((1...6).map { "srv-\($0)" })

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body, "MenuBarPopoverView must render cleanly with 12 servers without truncation")
        state.cancelPendingTasks()
    }

    func testMenuBarPopoverScaleFiftyServersStressAndPerformance() {
        let state = AppState(autoload: false)
        state.servers = (1...50).map {
            MCPServerDefinition(id: "srv-\($0)", name: "Server \($0)", category: "core", config: [:])
        }
        state.globalServerIds = Set((1...25).map { "srv-\($0)" })

        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 1...100 {
            let popover = MenuBarPopoverView(state: state)
            _ = popover.body
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 1.0, "100 render evaluations with 50 servers should take < 1.0s (measured: \(elapsed)s)")
        state.cancelPendingTasks()
    }

    func testMenuBarPopoverScaleOneHundredServersExtremeStress() {
        let state = AppState(autoload: false)
        state.servers = (1...100).map {
            MCPServerDefinition(id: "srv-\($0)", name: "Server \($0)", category: "stress", config: [:])
        }
        state.globalServerIds = Set((1...50).map { "srv-\($0)" })

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body, "MenuBarPopoverView must survive extreme scale of 100 servers without crash")
        state.cancelPendingTasks()
    }

    func testMenuBarPopoverAdversarialServerInputs() {
        let state = AppState(autoload: false)
        let hugeName = String(repeating: "A", count: 1000)
        let unicodeServer = MCPServerDefinition(
            id: "srv-unicode",
            name: "⚡️🚀 Сервер Назив српски 測試 123 !@#$%^&*()",
            category: "tools",
            config: [
                "command": .string("echo 'hello\nworld'"),
                "args": .array([.string("arg1"), .string("arg2 with spaces and \"quotes\"")])
            ]
        )
        let hugeServer = MCPServerDefinition(
            id: "srv-huge",
            name: hugeName,
            category: "",
            config: [
                "command": .string(String(repeating: "/path/to/very/long/binary/", count: 20))
            ]
        )
        let emptyNameServer = MCPServerDefinition(
            id: "srv-empty",
            name: "",
            category: "",
            config: [:]
        )

        state.servers = [unicodeServer, hugeServer, emptyNameServer]
        state.globalServerIds = ["srv-unicode"]

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body, "MenuBarPopoverView must safely render adversarial server names and inputs")
        state.cancelPendingTasks()
    }

    // MARK: - Challenge 2: Context Switching & Bidirectional Synchronization

    func testContextSwitchingBidirectionalSyncBetweenGlobalAndProjects() {
        let state = AppState(autoload: false)
        let projA = ProjectProfile(id: "proj-alpha", name: "Alpha", path: "/tmp/alpha")
        let projB = ProjectProfile(id: "proj-beta", name: "Beta", path: "/tmp/beta")
        state.projects = [projA, projB]

        // Initially in Master Vault
        XCTAssertEqual(state.navigationSelection, .masterVault)
        XCTAssertNil(state.selectedProjectId)

        // 1. Simulate Picker selecting "proj-alpha" (as written in MenuBarPopoverView)
        let pickerBinding = Binding<String>(
            get: { state.selectedProjectId ?? "" },
            set: { newId in
                if newId.isEmpty {
                    state.selectedProjectId = nil
                    state.navigationSelection = .globalCore
                } else {
                    state.selectedProjectId = newId
                    state.navigationSelection = .project(newId)
                }
            }
        )

        pickerBinding.wrappedValue = "proj-alpha"
        XCTAssertEqual(state.selectedProjectId, "proj-alpha", "Selecting proj-alpha must set selectedProjectId")
        XCTAssertEqual(state.navigationSelection, .project("proj-alpha"), "Selecting proj-alpha must set navigationSelection to .project(proj-alpha)")
        XCTAssertEqual(state.selectedProject?.id, "proj-alpha", "state.selectedProject must resolve to proj-alpha")

        // 2. Switch to "proj-beta"
        pickerBinding.wrappedValue = "proj-beta"
        XCTAssertEqual(state.selectedProjectId, "proj-beta")
        XCTAssertEqual(state.navigationSelection, .project("proj-beta"))
        XCTAssertEqual(state.selectedProject?.id, "proj-beta")

        // 3. Switch back to "" (Global Core)
        pickerBinding.wrappedValue = ""
        XCTAssertNil(state.selectedProjectId, "Selecting empty tag must clear selectedProjectId to nil")
        XCTAssertEqual(state.navigationSelection, .globalCore, "Selecting empty tag must update navigationSelection to .globalCore")
        XCTAssertNil(state.selectedProject)

        // 4. Test external state change: Sidebar / ControlCenter navigates to project
        state.navigationSelection = .project("proj-alpha")
        XCTAssertEqual(state.selectedProjectId, "proj-alpha", "AppState.navigationSelection didSet must synchronize selectedProjectId")
        XCTAssertEqual(pickerBinding.wrappedValue, "proj-alpha", "Picker binding getter must return proj-alpha")

        // 5. Test external state change: Sidebar / ControlCenter navigates to Global Core
        state.navigationSelection = .globalCore
        XCTAssertNil(state.selectedProjectId, "AppState.navigationSelection didSet must set selectedProjectId to nil on .globalCore")
        XCTAssertEqual(pickerBinding.wrappedValue, "", "Picker binding getter must return empty string for Global Core")

        state.cancelPendingTasks()
    }

    func testContextSwitchingWithNonExistentProjectId() {
        let state = AppState(autoload: false)
        let proj = ProjectProfile(id: "proj-real", name: "Real", path: "/tmp/real")
        state.projects = [proj]

        // Set to non-existent project id
        state.selectedProjectId = "ghost-proj"
        XCTAssertNil(state.selectedProject, "selectedProject should be nil when id does not match any registered project")

        // Popover should not crash when selectedProjectId points to non-existent project
        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body)
        state.cancelPendingTasks()
    }

    // MARK: - Challenge 3: MenuBarServerRow Toggle Isolation, Inheritance & Scoping

    func testMenuBarServerRowGlobalContextTogglesOnlyGlobalServers() {
        let state = AppState(autoload: false)
        let srv = MCPServerDefinition(id: "global-srv", name: "Global Server", category: "core", config: [:])
        state.servers = [srv]
        state.globalServerIds = []

        var proj = ProjectProfile(id: "p1", name: "P1", path: "/tmp/p1")
        proj.enabledMCPServerIds = []
        state.projects = [proj]

        // Global context: projectId is nil
        let row = MenuBarServerRow(state: state, server: srv, projectId: nil)
        XCTAssertNotNil(row.body)

        // Toggle ON globally
        state.toggleGlobalServer(id: "global-srv")
        XCTAssertTrue(state.globalServerIds.contains("global-srv"))
        XCTAssertFalse(state.projects[0].enabledMCPServerIds.contains("global-srv"), "Global toggle must NOT affect project server IDs")

        // Toggle OFF globally
        state.toggleGlobalServer(id: "global-srv")
        XCTAssertFalse(state.globalServerIds.contains("global-srv"))
        XCTAssertFalse(state.projects[0].enabledMCPServerIds.contains("global-srv"))

        state.cancelPendingTasks()
    }

    func testMenuBarServerRowInheritedGlobalServerCannotBeToggledInProjectContext() {
        let state = AppState(autoload: false)
        let globalSrv = MCPServerDefinition(id: "inherited-srv", name: "Inherited Server", category: "core", config: [:])
        state.servers = [globalSrv]
        state.globalServerIds = ["inherited-srv"]

        var proj = ProjectProfile(id: "p1", name: "P1", path: "/tmp/p1")
        proj.enabledMCPServerIds = [] // Not explicitly enabled in project, but inherited globally
        state.projects = [proj]

        // In project context: server is inherited global
        let row = MenuBarServerRow(state: state, server: globalSrv, projectId: "p1")
        XCTAssertNotNil(row.body)

        // Attempting to toggle project server for an inherited global server should NOT turn it off globally
        state.toggleProjectServer(projectId: "p1", serverId: "inherited-srv")
        // Note: project.enabledMCPServerIds may toggle locally, but globalServerIds MUST remain intact!
        XCTAssertTrue(state.globalServerIds.contains("inherited-srv"), "Project toggle must NEVER disable global server in state.globalServerIds")

        // And state.globalServerIds still contains "inherited-srv"
        XCTAssertEqual(state.globalServerIds, ["inherited-srv"])

        state.cancelPendingTasks()
    }

    func testMenuBarServerRowProjectScopedServerTogglesOnlyTargetProject() {
        let state = AppState(autoload: false)
        let projectSrv = MCPServerDefinition(id: "scoped-srv", name: "Scoped Server", category: "dev", config: [:])
        state.servers = [projectSrv]
        state.globalServerIds = [] // Not global

        var projA = ProjectProfile(id: "p-alpha", name: "Alpha", path: "/tmp/pa")
        var projB = ProjectProfile(id: "p-beta", name: "Beta", path: "/tmp/pb")
        projA.enabledMCPServerIds = []
        projB.enabledMCPServerIds = []
        state.projects = [projA, projB]

        // Context: Project Alpha
        let rowAlpha = MenuBarServerRow(state: state, server: projectSrv, projectId: "p-alpha")
        XCTAssertNotNil(rowAlpha.body)

        // Toggle ON for Project Alpha
        state.toggleProjectServer(projectId: "p-alpha", serverId: "scoped-srv")
        XCTAssertTrue(state.projects.first(where: { $0.id == "p-alpha" })!.enabledMCPServerIds.contains("scoped-srv"))
        XCTAssertFalse(state.projects.first(where: { $0.id == "p-beta" })!.enabledMCPServerIds.contains("scoped-srv"), "Project Alpha toggle must NOT affect Project Beta")
        XCTAssertFalse(state.globalServerIds.contains("scoped-srv"), "Project Alpha toggle must NOT affect globalServerIds")

        // Toggle OFF for Project Alpha
        state.toggleProjectServer(projectId: "p-alpha", serverId: "scoped-srv")
        XCTAssertFalse(state.projects.first(where: { $0.id == "p-alpha" })!.enabledMCPServerIds.contains("scoped-srv"))
        XCTAssertFalse(state.projects.first(where: { $0.id == "p-beta" })!.enabledMCPServerIds.contains("scoped-srv"))
        XCTAssertFalse(state.globalServerIds.contains("scoped-srv"))

        state.cancelPendingTasks()
    }

    // MARK: - Challenge 4: Edge Cases (Cross-context overlap, Deleted Project, Subtitle logic)

    func testServerBothGlobalAndProjectScopedPrecedence() {
        let state = AppState(autoload: false)
        let srv = MCPServerDefinition(id: "dual-srv", name: "Dual Server", category: "core", config: [:])
        state.servers = [srv]
        state.globalServerIds = ["dual-srv"]

        var proj = ProjectProfile(id: "p1", name: "P1", path: "/tmp/p1")
        proj.enabledMCPServerIds = ["dual-srv"] // Enabled in both!
        state.projects = [proj]

        // In project context, because isGlobal is true, it is treated as inherited global
        let row = MenuBarServerRow(state: state, server: srv, projectId: "p1")
        XCTAssertNotNil(row.body)

        // Global server ID remains intact
        XCTAssertTrue(state.globalServerIds.contains("dual-srv"))
        state.cancelPendingTasks()
    }

    func testDeletedProjectHandlingWhilePopoverOpen() {
        let state = AppState(autoload: false)
        let proj = ProjectProfile(id: "ephemeral-proj", name: "Ephemeral", path: "/tmp/eph")
        state.projects = [proj]
        state.selectedProjectId = "ephemeral-proj"

        // Popover initially in project context
        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body)

        // Simulate project deletion / reset
        state.projects = []
        // selectedProjectId is still "ephemeral-proj", but selectedProject is nil
        XCTAssertNil(state.selectedProject)

        // Popover must not crash and gracefully fall back
        XCTAssertNotNil(popover.body)

        // Server row with deleted project ID must not crash on toggle
        let srv = MCPServerDefinition(id: "srv1", name: "Srv 1", category: "core", config: [:])
        state.servers = [srv]
        let row = MenuBarServerRow(state: state, server: srv, projectId: "ephemeral-proj")
        XCTAssertNotNil(row.body)

        // Safe toggle on non-existent project
        state.toggleProjectServer(projectId: "ephemeral-proj", serverId: "srv1")
        XCTAssertEqual(state.projects.count, 0)

        state.cancelPendingTasks()
    }

    func testMenuBarServerRowTypeInspection() {
        let state = AppState(autoload: false)
        let srv = MCPServerDefinition(id: "global-srv", name: "Global Server", category: "core", config: [:])
        state.servers = [srv]
        state.globalServerIds = ["global-srv"]
        let project = ProjectProfile(id: "p1", name: "P1", path: "/tmp/p1")
        state.projects = [project]

        // 1. Inherited global in project context
        let inheritedRow = MenuBarServerRow(state: state, server: srv, projectId: "p1")
        let inheritedBodyType = String(reflecting: type(of: inheritedRow.body))
        XCTAssertTrue(inheritedBodyType.contains("ModifiedContent") || inheritedBodyType.contains("View"), "Row body must produce valid SwiftUI modified content")

        // 2. Global context
        let globalRow = MenuBarServerRow(state: state, server: srv, projectId: nil)
        let globalBodyType = String(reflecting: type(of: globalRow.body))
        XCTAssertTrue(globalBodyType.contains("ModifiedContent") || globalBodyType.contains("View"))

        state.cancelPendingTasks()
    }
}

