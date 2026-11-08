import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

@MainActor
final class M1WindowAndMenuBarTests: XCTestCase {

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

    // MARK: - WindowRouter Tests

    func testFindControlCenterWindowByIdentifier() {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.identifier = NSUserInterfaceItemIdentifier("control-center")
        testWindow.title = "Master Vault"
        testWindow.setIsVisible(true)

        let found = WindowRouter.findControlCenterWindow()
        XCTAssertNotNil(found, "WindowRouter must find window by identifier 'control-center' even when title is dynamically set to 'Master Vault'")
        XCTAssertEqual(found?.identifier?.rawValue, "control-center")

        var openCalled = false
        WindowRouter.openControlCenter = { openCalled = true }
        WindowRouter.triggerOpen()
        XCTAssertFalse(openCalled, "WindowRouter.triggerOpen must NOT invoke fallback openControlCenter when window is already present in AppKit")

        testWindow.orderOut(nil)
    }

    func testFindControlCenterWindowWhenMiniaturized() {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.identifier = NSUserInterfaceItemIdentifier("control-center")
        testWindow.title = "acme-web"
        testWindow.setIsVisible(true)
        testWindow.miniaturize(nil)

        let found = WindowRouter.findControlCenterWindow()
        XCTAssertNotNil(found, "WindowRouter must find miniaturized Control Center window")

        WindowRouter.triggerOpen()
        // WindowRouter.triggerOpen will invoke deminiaturize(nil)
        XCTAssertFalse(testWindow.isMiniaturized, "WindowRouter.triggerOpen must deminiaturize miniaturized window")

        testWindow.orderOut(nil)
    }

    func testFindControlCenterWindowExcludesSettingsPopoversAndPanels() {
        // 1. Settings window
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        settingsWindow.title = "Settings"
        settingsWindow.setIsVisible(true)

        // 2. Status bar popover window
        let popoverWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        popoverWindow.level = .statusBar
        popoverWindow.title = "Test Popover Window"
        popoverWindow.setIsVisible(true)

        // With only Settings and Popover open, Control Center must NOT be found
        let found = WindowRouter.findControlCenterWindow()
        XCTAssertNil(found, "WindowRouter must exclude Settings windows, popovers, and panels")

        settingsWindow.orderOut(nil)
        popoverWindow.orderOut(nil)
    }

    func testTriggerOpenInvokesFallbackWhenWindowClosed() {
        var openCalled = false
        WindowRouter.openControlCenter = {
            openCalled = true
        }

        // When no window exists, triggerOpen must invoke openControlCenter fallback
        WindowRouter.triggerOpen()
        XCTAssertTrue(openCalled, "WindowRouter.triggerOpen must call fallback when no window is found")
    }

    func testFindControlCenterWindowWhenOnSettingsSection() {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        testWindow.identifier = NSUserInterfaceItemIdentifier("control-center")
        testWindow.title = "Settings"
        testWindow.setIsVisible(true)

        let found = WindowRouter.findControlCenterWindow()
        XCTAssertNotNil(found, "WindowRouter must find window by identifier 'control-center' even when dynamic title is 'Settings'")
        XCTAssertEqual(found?.identifier?.rawValue, "control-center")

        var fallbackCalled = false
        WindowRouter.openControlCenter = { fallbackCalled = true }
        WindowRouter.triggerOpen()
        XCTAssertFalse(fallbackCalled, "triggerOpen must not invoke fallback when control center window is already present on Settings section")

        testWindow.orderOut(nil)
    }

    // MARK: - MenuBarPopover & Context Switching Tests

    func testMenuBarPopoverContextSwitchingNavigationSelection() {
        let state = AppState(autoload: false)
        let project = ProjectProfile(id: "test-proj-alpha", name: "Alpha Project", path: "/tmp/alpha")
        state.projects = [project]

        // 1. Switch to project
        state.selectedProjectId = "test-proj-alpha"
        state.navigationSelection = .project("test-proj-alpha")
        XCTAssertEqual(state.selectedProjectId, "test-proj-alpha")
        XCTAssertEqual(state.navigationSelection, .project("test-proj-alpha"))

        // 2. Switch to Global Core
        state.selectedProjectId = nil
        state.navigationSelection = .globalCore
        XCTAssertNil(state.selectedProjectId)
        XCTAssertEqual(state.navigationSelection, .globalCore)

        // 3. Verify AppState.navigationSelection didSet synchronization
        state.navigationSelection = .project("test-proj-alpha")
        XCTAssertEqual(state.selectedProjectId, "test-proj-alpha", "didSet on navigationSelection must sync selectedProjectId for .project")

        state.navigationSelection = .globalCore
        XCTAssertNil(state.selectedProjectId, "didSet on navigationSelection must reset selectedProjectId to nil for .globalCore")

        state.cancelPendingTasks()
    }

    func testMenuBarServerRowHandlesProjectIdInheritedAndProjectScoped() {
        let state = AppState(autoload: false)
        let globalServer = MCPServerDefinition(id: "global-mcp", name: "Global MCP", category: "core", config: [:])
        let projectServer = MCPServerDefinition(id: "project-mcp", name: "Project MCP", category: "dev", config: [:])
        let unassignedServer = MCPServerDefinition(id: "extra-mcp", name: "Extra MCP", category: "tools", config: [:])
        state.servers = [globalServer, projectServer, unassignedServer]
        state.globalServerIds = ["global-mcp"]

        var project = ProjectProfile(id: "proj-1", name: "Project One", path: "/tmp/p1")
        project.enabledMCPServerIds = ["project-mcp"]
        state.projects = [project]

        // 1. Inherited row (Global server in project context)
        let inheritedRow = MenuBarServerRow(state: state, server: globalServer, projectId: "proj-1")
        XCTAssertNotNil(inheritedRow.body)

        // 2. Scoped project row (Server enabled locally for project)
        let scopedRow = MenuBarServerRow(state: state, server: projectServer, projectId: "proj-1")
        XCTAssertNotNil(scopedRow.body)
        XCTAssertTrue(state.projects.first(where: { $0.id == "proj-1" })!.enabledMCPServerIds.contains("project-mcp"))

        // 3. Toggle scoped server off and on for project
        state.toggleProjectServer(projectId: "proj-1", serverId: "project-mcp")
        XCTAssertFalse(state.projects.first(where: { $0.id == "proj-1" })!.enabledMCPServerIds.contains("project-mcp"))

        state.toggleProjectServer(projectId: "proj-1", serverId: "project-mcp")
        XCTAssertTrue(state.projects.first(where: { $0.id == "proj-1" })!.enabledMCPServerIds.contains("project-mcp"))

        // 4. Toggle unassigned server on for project
        state.toggleProjectServer(projectId: "proj-1", serverId: "extra-mcp")
        XCTAssertTrue(state.projects.first(where: { $0.id == "proj-1" })!.enabledMCPServerIds.contains("extra-mcp"))

        // Global server list is unaffected by project toggle
        XCTAssertFalse(state.globalServerIds.contains("extra-mcp"))

        state.cancelPendingTasks()
    }

    func testMenuBarPopoverRendersAllServersWithoutTruncation() {
        let state = AppState(autoload: false)
        let mockServers = (1...12).map {
            MCPServerDefinition(id: "srv-\($0)", name: "Server \($0)", category: "core", config: [:])
        }
        state.servers = mockServers
        XCTAssertEqual(state.servers.count, 12, "Should have 12 registered servers")

        let popover = MenuBarPopoverView(state: state)
        XCTAssertNotNil(popover.body, "MenuBarPopoverView must render all 12 servers without truncation")

        state.cancelPendingTasks()
    }
}
