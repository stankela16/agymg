import XCTest
import SwiftUI
import Observation
@testable import AntigravityManager

private final class ObservationBox: @unchecked Sendable {
    var changed = false
}

@MainActor
final class StateReactivityTests: XCTestCase {
    private var testSandboxDir: URL!
    private var tempDir: URL {
        testSandboxDir
    }

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StateReactivityTests_\(UUID().uuidString)", isDirectory: true)
        let geminiDir = dir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = dir.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        testSandboxDir = dir
        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let dir = testSandboxDir {
            try? FileManager.default.removeItem(at: dir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    // MARK: - 1. Project Scoping and Active Project Transition
    func testProjectScopingAndActiveProjectTransition() {
        let state = AppState()
        let projectAlpha = ProjectProfile(
            id: "alpha",
            name: "Alpha Project",
            path: tempDir.appendingPathComponent("alpha").path
        )
        let projectBeta = ProjectProfile(
            id: "beta",
            name: "Beta Project",
            path: tempDir.appendingPathComponent("beta").path
        )

        state.projects = [projectAlpha, projectBeta]

        // Initially select Alpha
        state.selectedProjectId = "alpha"
        XCTAssertNotNil(state.selectedProject)
        XCTAssertEqual(state.selectedProject?.id, "alpha")
        XCTAssertEqual(state.selectedProject?.name, "Alpha Project")

        // Switch to Beta
        state.selectedProjectId = "beta"
        XCTAssertNotNil(state.selectedProject)
        XCTAssertEqual(state.selectedProject?.id, "beta")
        XCTAssertEqual(state.selectedProject?.name, "Beta Project")

        // Switch to non-existent ID
        state.selectedProjectId = "non-existent"
        XCTAssertNil(state.selectedProject)

        // Reset to nil
        state.selectedProjectId = nil
        XCTAssertNil(state.selectedProject)
        state.cancelPendingTasks()
    }

    // MARK: - 2. Global Toggles State Reactivity
    func testGlobalTogglesStateReactivity() {
        let state = AppState()
        state.globalServerIds = []
        state.globalSkillIds = []
        state.globalPluginIds = []

        // 1. Toggle global server
        XCTAssertFalse(state.globalServerIds.contains("github"))
        state.toggleGlobalServer(id: "github")
        XCTAssertTrue(state.globalServerIds.contains("github"))
        state.toggleGlobalServer(id: "github")
        XCTAssertFalse(state.globalServerIds.contains("github"))

        // 2. Toggle global skill
        XCTAssertFalse(state.globalSkillIds.contains("ask"))
        state.toggleGlobalSkill(id: "ask")
        XCTAssertTrue(state.globalSkillIds.contains("ask"))
        state.toggleGlobalSkill(id: "ask")
        XCTAssertFalse(state.globalSkillIds.contains("ask"))

        // 3. Toggle global plugin
        XCTAssertFalse(state.globalPluginIds.contains("chrome-devtools"))
        state.toggleGlobalPlugin(id: "chrome-devtools")
        XCTAssertTrue(state.globalPluginIds.contains("chrome-devtools"))
        state.toggleGlobalPlugin(id: "chrome-devtools")
        XCTAssertFalse(state.globalPluginIds.contains("chrome-devtools"))
        state.cancelPendingTasks()
    }

    // MARK: - 3. Cross-Project Resource Isolation
    func testCrossProjectResourceIsolation() {
        let state = AppState()
        let projectA = ProjectProfile(
            id: "project-a",
            name: "Project A",
            path: tempDir.appendingPathComponent("proj_a").path,
            enabledMCPServerIds: ["server-init-a"],
            enabledSkillIds: ["skill-init-a"],
            enabledPluginIds: ["plugin-init-a"]
        )
        let projectB = ProjectProfile(
            id: "project-b",
            name: "Project B",
            path: tempDir.appendingPathComponent("proj_b").path,
            enabledMCPServerIds: [],
            enabledSkillIds: [],
            enabledPluginIds: []
        )

        state.projects = [projectA, projectB]
        state.globalServerIds = ["global-srv"]
        state.globalSkillIds = ["global-sk"]
        state.globalPluginIds = ["global-plg"]

        // Mutate Project A via toggles
        state.toggleProjectServer(projectId: "project-a", serverId: "server-new-a")
        state.toggleProjectSkill(projectId: "project-a", skillId: "skill-new-a")
        state.toggleProjectPlugin(projectId: "project-a", pluginId: "plugin-new-a")

        guard let updatedA = state.projects.first(where: { $0.id == "project-a" }),
              let updatedB = state.projects.first(where: { $0.id == "project-b" }) else {
            XCTFail("Projects must exist in state")
            return
        }

        // Verify Project A has updated sets
        XCTAssertTrue(updatedA.enabledMCPServerIds.contains("server-init-a"))
        XCTAssertTrue(updatedA.enabledMCPServerIds.contains("server-new-a"))
        XCTAssertTrue(updatedA.enabledSkillIds.contains("skill-init-a"))
        XCTAssertTrue(updatedA.enabledSkillIds.contains("skill-new-a"))
        XCTAssertTrue(updatedA.enabledPluginIds.contains("plugin-init-a"))
        XCTAssertTrue(updatedA.enabledPluginIds.contains("plugin-new-a"))

        // Verify Project B was NOT polluted
        XCTAssertTrue(updatedB.enabledMCPServerIds.isEmpty, "Project B server IDs must remain empty")
        XCTAssertTrue(updatedB.enabledSkillIds.isEmpty, "Project B skill IDs must remain empty")
        XCTAssertTrue(updatedB.enabledPluginIds.isEmpty, "Project B plugin IDs must remain empty")

        // Verify Global Core selection was NOT polluted
        XCTAssertEqual(state.globalServerIds, ["global-srv"])
        XCTAssertEqual(state.globalSkillIds, ["global-sk"])
        XCTAssertEqual(state.globalPluginIds, ["global-plg"])
        state.cancelPendingTasks()
    }

    // MARK: - 4. Project Removal Scoping Fallback
    func testProjectRemovalScopingFallback() async {
        let state = AppState()
        let p1 = ProjectProfile(id: "proj-1", name: "Project One", path: tempDir.appendingPathComponent("p1").path)
        let p2 = ProjectProfile(id: "proj-2", name: "Project Two", path: tempDir.appendingPathComponent("p2").path)
        let p3 = ProjectProfile(id: "proj-3", name: "Project Three", path: tempDir.appendingPathComponent("p3").path)

        state.projects = [p1, p2, p3]
        state.selectedProjectId = "proj-1"
        state.navigationSelection = .project("proj-1")

        // Remove active project p1 -> should fall back to p2
        await state.removeProject(id: "proj-1")
        XCTAssertEqual(state.projects.count, 2)
        XCTAssertFalse(state.projects.contains(where: { $0.id == "proj-1" }))
        XCTAssertEqual(state.selectedProjectId, "proj-2")
        XCTAssertEqual(state.navigationSelection, .project("proj-2"))

        // Remove active project p2 -> should fall back to p3
        await state.removeProject(id: "proj-2")
        XCTAssertEqual(state.projects.count, 1)
        XCTAssertFalse(state.projects.contains(where: { $0.id == "proj-2" }))
        XCTAssertEqual(state.selectedProjectId, "proj-3")
        XCTAssertEqual(state.navigationSelection, .project("proj-3"))

        // Remove last project p3 -> should fall back to nil and .masterVault
        await state.removeProject(id: "proj-3")
        XCTAssertTrue(state.projects.isEmpty)
        XCTAssertNil(state.selectedProjectId)
        XCTAssertEqual(state.navigationSelection, .masterVault)
        state.cancelPendingTasks()
    }

    // MARK: - 5. Observation Tracking Reactivity
    func testObservationTrackingReactivity() {
        let state = AppState()

        // Test 1: Tracking selectedProjectId mutation
        let selectedIdBox = ObservationBox()
        withObservationTracking {
            _ = state.selectedProjectId
        } onChange: {
            selectedIdBox.changed = true
        }

        XCTAssertFalse(selectedIdBox.changed)
        state.selectedProjectId = "new-tracked-id"
        XCTAssertTrue(selectedIdBox.changed, "withObservationTracking must trigger onChange when selectedProjectId mutates")

        // Test 2: Tracking projects array mutation
        let projectsBox = ObservationBox()
        withObservationTracking {
            _ = state.projects.count
        } onChange: {
            projectsBox.changed = true
        }

        XCTAssertFalse(projectsBox.changed)
        state.projects.append(ProjectProfile(id: "tracked-proj", name: "Tracked", path: tempDir.path))
        XCTAssertTrue(projectsBox.changed, "withObservationTracking must trigger onChange when projects array mutates")

        // Test 3: Tracking globalServerIds mutation
        let globalServersBox = ObservationBox()
        withObservationTracking {
            _ = state.globalServerIds
        } onChange: {
            globalServersBox.changed = true
        }

        XCTAssertFalse(globalServersBox.changed)
        state.globalServerIds.insert("new-srv")
        XCTAssertTrue(globalServersBox.changed, "withObservationTracking must trigger onChange when globalServerIds mutates")
        state.cancelPendingTasks()
    }

    // MARK: - 6. Runtime Manifest Computed Properties
    func testRuntimeManifestComputedProperties() throws {
        let serverA = MCPServerDefinition(
            id: "srv-alpha",
            name: "Server Alpha",
            category: "core",
            config: ["command": .string("node"), "args": .array([.string("dist/index.js")])]
        )
        let serverB = MCPServerDefinition(
            id: "srv-beta",
            name: "Server Beta",
            category: "tools",
            config: ["command": .string("python3"), "args": .array([.string("app.py")])]
        )
        let serverC = MCPServerDefinition(
            id: "srv-gamma",
            name: "Server Gamma",
            category: "cloud",
            config: ["command": .string("go")]
        )
        let allServers = [serverA, serverB, serverC]

        var project = ProjectProfile(
            id: "manifest-proj",
            name: "Manifest Project",
            path: tempDir.appendingPathComponent("manifest-proj").path,
            enabledMCPServerIds: ["srv-alpha", "srv-beta"],
            enabledSkillIds: ["skill-z", "skill-a"],
            enabledPluginIds: ["plugin-1"]
        )

        // Generate initial manifest
        let jsonString = RuntimeManifestPreviewView.generateManifestJSON(project: project, servers: allServers)
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("generateManifestJSON must produce valid JSON")
            return
        }

        XCTAssertNil(json["schemaVersion"], "Preview must match real mcp_config.json without fake schemaVersion")

        guard let serversDict = json["mcpServers"] as? [String: [String: Any]] else {
            XCTFail("Manifest must contain mcpServers dictionary")
            return
        }

        // Servers count: srv-alpha and srv-beta enabled, srv-gamma excluded
        XCTAssertEqual(serversDict.count, 2)
        XCTAssertNotNil(serversDict["srv-alpha"])
        XCTAssertNotNil(serversDict["srv-beta"])
        XCTAssertNil(serversDict["srv-gamma"])
        XCTAssertEqual(serversDict["srv-alpha"]?["command"] as? String, "node")
        XCTAssertEqual(serversDict["srv-alpha"]?["args"] as? [String], ["dist/index.js"])

        // Modify project: enable srv-gamma, disable srv-alpha
        project.enabledMCPServerIds = ["srv-beta", "srv-gamma"]
        let updatedJsonString = RuntimeManifestPreviewView.generateManifestJSON(project: project, servers: allServers)
        guard let updatedData = updatedJsonString.data(using: .utf8),
              let updatedJson = try JSONSerialization.jsonObject(with: updatedData) as? [String: Any],
              let updatedServersDict = updatedJson["mcpServers"] as? [String: [String: Any]] else {
            XCTFail("Updated manifest must be valid JSON")
            return
        }

        XCTAssertEqual(updatedServersDict.count, 2)
        XCTAssertNil(updatedServersDict["srv-alpha"])
        XCTAssertNotNil(updatedServersDict["srv-beta"])
        XCTAssertNotNil(updatedServersDict["srv-gamma"])
    }
}
