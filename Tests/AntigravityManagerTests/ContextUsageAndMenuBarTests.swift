import XCTest
import AppKit
@testable import AntigravityManager

@MainActor
final class ContextUsageAndMenuBarTests: XCTestCase {

    func testMenuBarIconIsRetinaHiDPIAndHasNoNotificationDot() throws {
        let icon = try XCTUnwrap(MenuBarIconProvider.icon)
        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size.width, 18, accuracy: 0.1)
        XCTAssertEqual(icon.size.height, 18, accuracy: 0.1)

        // Ensure a @2x Retina representation (36x36 px) is attached so HiDPI menu bars stay sharp.
        let hasHiDPI = icon.representations.contains { rep in
            rep.pixelsWide >= 36 && rep.pixelsHigh >= 36
        }
        XCTAssertTrue(hasHiDPI, "MenuBar icon must include a >=36x36 Retina representation")

        // Ensure the notification dot is completely removed regardless of recommendations.
        let withRecs = MenuBarIconProvider.icon(hasRecommendations: true)
        let withoutRecs = MenuBarIconProvider.icon(hasRecommendations: false)
        XCTAssertTrue(withRecs === withoutRecs, "MenuBar icon must not render a recommendation dot")
    }

    func testContextUsageServiceParsesFootprintsAnd30DayTranscripts() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("agymg-usage-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }

        let skillDir = tmp.appendingPathComponent("skills/demo-skill", isDirectory: true)
        let mcpSchemaDir = tmp.appendingPathComponent("mcp/heavy-mcp", isDirectory: true)
        let claudeProjDir = tmp.appendingPathComponent("claude/-Users-dev-sample-app", isDirectory: true)
        let brainConvDir = tmp.appendingPathComponent("brain/conv-1/.system_generated/logs", isDirectory: true)
        let oldBrainConvDir = tmp.appendingPathComponent("brain/conv-old/.system_generated/logs", isDirectory: true)

        for dir in [skillDir, mcpSchemaDir, claudeProjDir, brainConvDir, oldBrainConvDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Write SKILL.md with frontmatter + body
        let skillContent = """
        ---
        name: demo-skill
        description: Short description for startup context testing.
        ---
        # Demo Skill
        \(String(repeating: "Detailed instruction line. ", count: 80))
        """
        try skillContent.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Write 2 cached MCP tool schemas (~4KB total)
        let schemaPayload = String(repeating: "a", count: 2048)
        try schemaPayload.write(to: mcpSchemaDir.appendingPathComponent("tool1.json"), atomically: true, encoding: .utf8)
        try schemaPayload.write(to: mcpSchemaDir.appendingPathComponent("tool2.json"), atomically: true, encoding: .utf8)

        // Write a recent Claude Code transcript invoking used-mcp twice and demo-skill once
        let claudeLog = """
        {"type":"tool_use","name":"mcp__used-mcp__search"}
        {"type":"tool_use","name":"mcp__used-mcp__read"}
        {"type":"tool_use","name":"Skill","input":{"skill":"demo-skill"}}
        """
        try claudeLog.write(to: claudeProjDir.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)

        // Write a recent Antigravity transcript in web-app invoking heavy-mcp once
        let agyLog = """
        {"content":"Working in /Users/dev/web-app/src"}
        {"tool_calls":[{"name":"call_mcp_tool","arguments":{"ServerName":"heavy-mcp"}}]}
        """
        try agyLog.write(to: brainConvDir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        // Write an old Antigravity transcript (>30 days) that must be ignored
        let oldTranscriptURL = oldBrainConvDir.appendingPathComponent("transcript.jsonl")
        try """
        {"content":"Working in /Users/dev/sample-app/App"}
        {"tool_calls":[{"name":"call_mcp_tool","arguments":{"ServerName":"heavy-mcp"}}]}
        """.write(to: oldTranscriptURL, atomically: true, encoding: .utf8)
        let oldDate = Date().addingTimeInterval(-45 * 86_400)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldTranscriptURL.path)

        let service = ContextUsageService(configuration: .init(
            claudeProjectsRoot: tmp.appendingPathComponent("claude", isDirectory: true),
            antigravityBrainRoots: [tmp.appendingPathComponent("brain", isDirectory: true)],
            antigravityMCPSchemaRoots: [tmp.appendingPathComponent("mcp", isDirectory: true)],
            observationWindowDays: 30
        ))

        let servers = [
            MCPServerDefinition(id: "heavy-mcp", name: "Heavy MCP", config: ["command": .string("node")]),
            MCPServerDefinition(id: "used-mcp", name: "Used MCP", config: ["command": .string("node")])
        ]
        let skills = [
            SkillDefinition(id: "demo-skill", name: "Demo Skill", description: "Short", path: skillDir.path)
        ]
        let projects = [
            ProjectProfile(id: "sample-app", name: "sample-app", path: "/Users/dev/sample-app", enabledMCPServerIds: ["used-mcp"], enabledSkillIds: ["demo-skill"]),
            ProjectProfile(id: "web-app", name: "web-app", path: "/Users/dev/web-app")
        ]

        let snapshot = await service.computeSnapshot(servers: servers, skills: skills, projects: projects)
        XCTAssertEqual(snapshot.scannedSessionsCount, 2, "Old >30d transcript must be excluded")
        XCTAssertEqual(snapshot.mcpFootprint(for: "heavy-mcp").toolCount, 2)
        XCTAssertGreaterThan(snapshot.mcpFootprint(for: "heavy-mcp").claudeStartupTokens, 900)
        XCTAssertLessThan(snapshot.skillFootprint(for: "demo-skill").antigravityStartupTokens, snapshot.skillFootprint(for: "demo-skill").onDemandTokens)

        XCTAssertEqual(snapshot.mcpStats(for: "used-mcp").calls(inProject: "sample-app"), 2)
        XCTAssertEqual(snapshot.mcpStats(for: "heavy-mcp").calls(inProject: "sample-app"), 0)
        XCTAssertEqual(snapshot.mcpStats(for: "heavy-mcp").calls(inProject: "web-app"), 1)
        XCTAssertEqual(snapshot.skillStats(for: "demo-skill").calls(inProject: "sample-app"), 1)

        let sampleSummary = snapshot.summary(
            for: projects[0],
            globalServerIds: ["heavy-mcp"],
            globalSkillIds: []
        )
        XCTAssertEqual(sampleSummary.dormantGlobalMCPIds, ["heavy-mcp"])
        XCTAssertTrue(sampleSummary.dormantProjectMCPIds.isEmpty)
        XCTAssertEqual(sampleSummary.health, ContextHealthLevel.clean)
    }

    func testGlobalToggleFromProjectWithUndoAndDormantCleanup() {
        let state = AppState(autoload: false)
        state.servers = [
            MCPServerDefinition(id: "db-mcp", name: "DB MCP", config: ["command": .string("npx")]),
            MCPServerDefinition(id: "mail-mcp", name: "Mail MCP", config: ["command": .string("npx")]),
            MCPServerDefinition(id: "active-mcp", name: "Active", config: ["command": .string("npx")])
        ]
        state.projects = [
            ProjectProfile(id: "sample", name: "sample-app", path: "/tmp/sample", enabledMCPServerIds: ["mail-mcp", "active-mcp"]),
            ProjectProfile(id: "web", name: "web-app", path: "/tmp/web")
        ]
        state.globalServerIds = ["db-mcp"]
        state.contextUsage = ContextUsageSnapshot(
            mcpUsage: [
                "db-mcp": ResourceUsageStats(totalCalls30d: 12, callsByProjectId: ["web": 12]),
                "active-mcp": ResourceUsageStats(totalCalls30d: 4, callsByProjectId: ["sample": 4])
            ],
            scannedSessionsCount: 5
        )

        // 1. Disabling global server from project sets Undo feedback
        state.disableGlobalServerFromProject(id: "db-mcp")
        XCTAssertFalse(state.globalServerIds.contains("db-mcp"))
        XCTAssertEqual(state.popoverFeedback?.undoAction, .reenableGlobalServer(id: "db-mcp"))

        // 2. Undo restores it to Global Core
        state.performPopoverUndo()
        XCTAssertTrue(state.globalServerIds.contains("db-mcp"))

        // 3. Move to Used Projects Only removes from Global Core and enables only on "web"
        state.moveGlobalResourceToUsedProjects(kind: .mcp, id: "db-mcp")
        XCTAssertFalse(state.globalServerIds.contains("db-mcp"))
        XCTAssertTrue(state.projects.first(where: { $0.id == "web" })?.enabledMCPServerIds.contains("db-mcp") == true)
        XCTAssertFalse(state.projects.first(where: { $0.id == "sample" })?.enabledMCPServerIds.contains("db-mcp") == true)

        // 4. Disable Dormant on "sample" disables "mail-mcp" (0 calls) and keeps "active-mcp" (4 calls)
        state.disableDormantProjectResources(projectId: "sample")
        let sampleMCPs = state.projects.first(where: { $0.id == "sample" })?.enabledMCPServerIds ?? []
        XCTAssertFalse(sampleMCPs.contains("mail-mcp"))
        XCTAssertTrue(sampleMCPs.contains("active-mcp"))

        state.cancelPendingTasks()
    }
}
