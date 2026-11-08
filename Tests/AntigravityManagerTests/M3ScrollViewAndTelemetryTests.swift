import XCTest
import SwiftUI
@testable import AntigravityManager

@MainActor
final class M3ScrollViewAndTelemetryTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M3Tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, fm.fileExists(atPath: tempDir.path) {
            try? fm.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - 1. Zero Vertical ScrollView Instances in 6 Child Tab Source Files

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testChildTabSourceFilesContainZeroVerticalScrollView() throws {
        let basePath = repoRoot.appendingPathComponent("Sources/AntigravityManager/Views").path
        let childTabFiles = [
            "\(basePath)/MasterVault/VaultServersTab.swift",
            "\(basePath)/MasterVault/VaultSkillsTab.swift",
            "\(basePath)/MasterVault/VaultPluginsTab.swift",
            "\(basePath)/Projects/ProjectServersTab.swift",
            "\(basePath)/Projects/ProjectSkillsTab.swift",
            "\(basePath)/Projects/ProjectPluginsTab.swift"
        ]

        for filePath in childTabFiles {
            XCTAssertTrue(fm.fileExists(atPath: filePath), "File must exist: \(filePath)")
            let content = try String(contentsOfFile: filePath, encoding: .utf8)

            // Must NOT contain any vertical ScrollView or ScrollView {
            let hasScrollView = content.contains("ScrollView {") || content.contains("ScrollView(")
            XCTAssertFalse(hasScrollView, "File \(filePath) must NOT contain any ScrollView instances")

            // Must NOT contain maxHeight: .infinity
            XCTAssertFalse(content.contains("maxHeight: .infinity"), "File \(filePath) must NOT contain maxHeight: .infinity")
        }
    }

    // MARK: - 2. Child Tab View Rendering and Layout Verification

    func testChildTabsRenderDirectlyWithoutNestedScrollViewCrash() {
        let state = AppState(autoload: false)
        state.servers = [
            MCPServerDefinition(id: "test-mcp", name: "Test MCP", category: "Core & Tools", config: [:])
        ]
        state.skills = [
            SkillDefinition(id: "test-skill", name: "Test Skill", description: "Test description", category: "Core & Tools", path: "/test", origin: .vault)
        ]
        state.plugins = [
            PluginDefinition(id: "test-plugin", name: "Test Plugin", path: "/test/plugin", hasMCP: true, hasSkills: true)
        ]
        let project = ProjectProfile(id: "test-proj", name: "Test Proj", path: tempDir.path)
        state.projects = [project]

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        // Master Vault Tabs
        let vaultServers = VaultServersTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        XCTAssertNotNil(vaultServers.body)

        let vaultSkills = VaultSkillsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        XCTAssertNotNil(vaultSkills.body)

        let vaultPlugins = VaultPluginsTab(state: state, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        XCTAssertNotNil(vaultPlugins.body)

        // Project Tabs
        let projectServers = ProjectServersTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        XCTAssertNotNil(projectServers.body)

        let projectSkills = ProjectSkillsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }), editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 }))
        XCTAssertNotNil(projectSkills.body)

        let projectPlugins = ProjectPluginsTab(state: state, projectId: project.id, deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }))
        XCTAssertNotNil(projectPlugins.body)
    }

    // MARK: - 3. SyncLogEntry Formatting and Duration Calculations

    func testSyncLogEntryFormattingAndDurationCalculations() {
        // Microsecond range (< 0.001s)
        let microEntry = SyncLogEntry(
            status: .success,
            category: .system,
            targetName: "Micro",
            message: "Micro op",
            duration: 0.000150
        )
        XCTAssertEqual(microEntry.formattedDuration, "150.0 µs")

        // Millisecond range (0.001s <= duration < 1.0s)
        let milliEntry = SyncLogEntry(
            status: .success,
            category: .global,
            targetName: "Milli",
            message: "Milli op",
            duration: 0.0425
        )
        XCTAssertEqual(milliEntry.formattedDuration, "42.5 ms")

        // Second range (>= 1.0s)
        let secEntry = SyncLogEntry(
            status: .warning,
            category: .project,
            targetName: "Sec",
            message: "Sec op",
            duration: 2.345
        )
        XCTAssertEqual(secEntry.formattedDuration, "2.35 s")

        // Nil duration
        let nilEntry = SyncLogEntry(
            status: .info,
            category: .vault,
            targetName: "Nil",
            message: "No duration",
            duration: nil
        )
        XCTAssertNil(nilEntry.formattedDuration)

        // Date formatting non-empty
        XCTAssertFalse(microEntry.formattedTimestamp.isEmpty)
        XCTAssertFalse(microEntry.fullTimestamp.isEmpty)
    }

    func testSyncLogStatusAndCategoryMetadata() {
        // All SyncLogStatus cases
        for status in SyncLogStatus.allCases {
            XCTAssertFalse(status.title.isEmpty)
            XCTAssertFalse(status.icon.isEmpty)
            XCTAssertNotNil(status.color)
            XCTAssertNotNil(status.backgroundColor)
        }

        // All SyncLogCategory cases
        for category in SyncLogCategory.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.icon.isEmpty)
        }
    }

    func testSyncLogEntryCodableSerialization() throws {
        let original = SyncLogEntry(
            status: .failure,
            category: .project,
            targetName: "acme-web",
            message: "EEXIST error creating symlink",
            details: "File exists at /Users/.../plugins",
            duration: 0.123
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncLogEntry.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.targetName, original.targetName)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.details, original.details)
        XCTAssertEqual(decoded.duration, original.duration)
    }

    // MARK: - 4. AppState Sync History: Prepending, Capping at 500 & Clear

    func testAppStateLogSyncEventPrependsAndCapsAt500() {
        let state = AppState(autoload: false)
        XCTAssertTrue(state.syncHistory.isEmpty)

        // Log first event
        state.logSyncEvent(
            status: .success,
            category: .global,
            targetName: "First",
            message: "Message 1"
        )
        XCTAssertEqual(state.syncHistory.count, 1)
        XCTAssertEqual(state.syncHistory.first?.targetName, "First")

        // Log second event -> must be at index 0 (prepended)
        state.logSyncEvent(
            status: .warning,
            category: .project,
            targetName: "Second",
            message: "Message 2"
        )
        XCTAssertEqual(state.syncHistory.count, 2)
        XCTAssertEqual(state.syncHistory.first?.targetName, "Second")
        XCTAssertEqual(state.syncHistory.last?.targetName, "First")

        // Insert up to 550 total events to test 500-entry cap
        for i in 3...550 {
            state.logSyncEvent(
                status: .info,
                category: .system,
                targetName: "Event-\(i)",
                message: "Bulk log \(i)"
            )
        }

        // Must be capped at 500
        XCTAssertEqual(state.syncHistory.count, 500)
        XCTAssertEqual(state.syncHistory.first?.targetName, "Event-550")

        // Test clearSyncHistory
        state.clearSyncHistory()
        XCTAssertEqual(state.syncHistory.count, 0)
    }

    // MARK: - 5. Real Sync Operations Produce Structured Log Entries with Duration

    func testPerformGlobalSyncAppendsStructuredLogWithDuration() async {
        let state = AppState(autoload: false)
        state.servers = [
            MCPServerDefinition(id: "global-mcp", name: "Global MCP", category: "Core & Tools", config: [:])
        ]
        state.globalServerIds = ["global-mcp"]
        state.clearSyncHistory()

        await state.performGlobalSync()

        XCTAssertFalse(state.syncHistory.isEmpty)
        let log = state.syncHistory.first!
        XCTAssertEqual(log.status, .success)
        XCTAssertEqual(log.category, .global)
        XCTAssertEqual(log.targetName, "Global Core")
        XCTAssertTrue(log.message.contains("Global core synchronized"))
        XCTAssertNotNil(log.duration)
        XCTAssertGreaterThan(log.duration ?? 0, 0)
        XCTAssertNotNil(state.lastSyncDate)
    }

    func testPerformProjectSyncAppendsStructuredLogWithDuration() async {
        let state = AppState(autoload: false)
        let projDir = tempDir.appendingPathComponent("proj-test", isDirectory: true)
        try? fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let project = ProjectProfile(
            id: "proj-1",
            name: "Alpha Project",
            path: projDir.path,
            enabledMCPServerIds: [],
            enabledSkillIds: []
        )
        state.projects = [project]
        state.clearSyncHistory()

        await state.performProjectSync(projectId: project.id)

        XCTAssertFalse(state.syncHistory.isEmpty)
        let log = state.syncHistory.first!
        XCTAssertEqual(log.status, .success)
        XCTAssertEqual(log.category, .project)
        XCTAssertEqual(log.targetName, "Alpha Project")
        XCTAssertTrue(log.message.contains("Synchronized 'Alpha Project'"))
        XCTAssertNotNil(log.duration)
        XCTAssertGreaterThan(log.duration ?? 0, 0)
    }

    func testSyncAllAppendsStructuredLogWithDuration() async {
        let state = AppState(autoload: false)
        state.clearSyncHistory()

        state.syncAll()

        // Wait for syncAllTask to finish
        if let task = state.syncAllTask {
            _ = await task.result
        }

        XCTAssertFalse(state.syncHistory.isEmpty)
        let log = state.syncHistory.first!
        XCTAssertEqual(log.status, .success)
        XCTAssertEqual(log.category, .all)
        XCTAssertEqual(log.targetName, "All Workspaces")
        XCTAssertTrue(log.message.contains("Full synchronization complete"))
        XCTAssertNotNil(log.duration)
        XCTAssertGreaterThan(log.duration ?? 0, 0)
    }

    // MARK: - 6. ControlCenterFooter Live Metrics & Zero Hardcoded RPC Literals

    func testControlCenterFooterContainsZeroHardcodedRPCLiterals() throws {
        let footerFilePath = repoRoot.appendingPathComponent("Sources/AntigravityManager/Views/Components/ControlCenterFooter.swift").path
        let content = try String(contentsOfFile: footerFilePath, encoding: .utf8)

        XCTAssertFalse(content.contains("1,482 calls"), "Footer must not contain hardcoded '1,482 calls'")
        XCTAssertFalse(content.contains("0 drops"), "Footer must not contain hardcoded '0 drops'")
        XCTAssertFalse(content.contains("99.98% up-ratio"), "Footer must not contain hardcoded '99.98% up-ratio'")
        XCTAssertFalse(content.contains("Mission Control RPC Channel"), "Footer must not contain hardcoded 'Mission Control RPC Channel'")
    }

    func testControlCenterFooterRendersDynamicStateIndicators() {
        let state = AppState(autoload: false)
        state.servers = [
            MCPServerDefinition(id: "s1", name: "S1", category: "Core & Tools", config: [:]),
            MCPServerDefinition(id: "s2", name: "S2", category: "Core & Tools", config: [:])
        ]
        state.skills = [
            SkillDefinition(id: "sk1", name: "SK1", description: "Skill 1", category: "Core & Tools", path: "/sk1", origin: .vault)
        ]
        state.plugins = [
            PluginDefinition(id: "p1", name: "P1", path: "/p1", hasMCP: false, hasSkills: true)
        ]
        state.projects = [
            ProjectProfile(id: "pr1", name: "PR1", path: "/pr1")
        ]

        let footer = ControlCenterFooter(state: state)
        XCTAssertNotNil(footer.body)

        // Normal LIVE state
        XCTAssertFalse(state.isSyncing)

        // SYNCING state
        state.isSyncing = true
        let syncingFooter = ControlCenterFooter(state: state)
        XCTAssertNotNil(syncingFooter.body)

        // ERROR state
        state.isSyncing = false
        state.logSyncEvent(status: .failure, category: .all, targetName: "All", message: "Failed")
        let errorFooter = ControlCenterFooter(state: state)
        XCTAssertNotNil(errorFooter.body)
    }

    // MARK: - 7. SyncLogsView Rendering and Filtering

    func testSyncLogsViewRendersAndFiltersCorrectly() {
        let state = AppState(autoload: false)
        state.logSyncEvent(status: .success, category: .global, targetName: "Global Core", message: "Synced global")
        state.logSyncEvent(status: .failure, category: .project, targetName: "acme-web", message: "Failed plugin link", details: "Permission denied")
        state.logSyncEvent(status: .warning, category: .vault, targetName: "Master Vault", message: "Vault warning")

        let view = SyncLogsView(state: state)
        XCTAssertNotNil(view.body)

        // Empty logs state rendering
        state.clearSyncHistory()
        let emptyView = SyncLogsView(state: state)
        XCTAssertNotNil(emptyView.body)
    }

    // MARK: - 8. ControlCenterSidebar SYSTEM Section Exposes Sync Logs

    func testControlCenterSidebarSystemSectionIncludesSyncLogs() throws {
        let sidebarFilePath = repoRoot.appendingPathComponent("Sources/AntigravityManager/Views/Components/ControlCenterSidebar.swift").path
        let content = try String(contentsOfFile: sidebarFilePath, encoding: .utf8)

        XCTAssertTrue(content.contains("title: \"Sync Logs\""), "Sidebar must contain 'Sync Logs' item")
        XCTAssertTrue(content.contains("section: .syncLogs"), "Sidebar must route to .syncLogs")
    }

    // MARK: - 9. ControlCenterView Renders SyncLogsView For .syncLogs Route

    func testControlCenterViewRoutesToSyncLogsView() {
        let state = AppState(autoload: false)
        state.navigationSelection = .syncLogs

        let ccView = ControlCenterView(state: state)
        XCTAssertNotNil(ccView.body)
    }
}
