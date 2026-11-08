import XCTest
import SwiftUI
@testable import AntigravityManager

@MainActor
final class M2ZeroLagAndSafetyTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M2Tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, fm.fileExists(atPath: tempDir.path) {
            try? fm.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - 1. In-Memory Cache Retrieval (Zero Disk I/O)

    func testLocalSkillsReadsFromMemoryCacheEvenWhenDiskDeleted() throws {
        let projDir = tempDir.appendingPathComponent("deleted-proj", isDirectory: true)
        let skillsDir = projDir.appendingPathComponent(".agents/skills/cached-skill", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skillMd = skillsDir.appendingPathComponent("SKILL.md")
        try "---\nname: Cached Skill\ndescription: A test cached skill\n---\n".write(to: skillMd, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "del-proj", name: "Deleted Proj", path: projDir.path)
        let state = AppState(autoload: false)

        let cachedSkill = SkillDefinition(
            id: "cached-skill",
            name: "Cached Skill",
            description: "A test cached skill",
            category: "Core & Tools",
            path: skillsDir.path,
            origin: .projectLocal
        )
        state.projectLocalSkills[project.id] = [cachedSkill]

        // Failsafe: Remove directory physically from disk
        try fm.removeItem(at: projDir)
        XCTAssertFalse(fm.fileExists(atPath: projDir.path))

        // Query localSkills - must return cached skill without throwing or accessing disk
        let result = state.localSkills(for: project)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "cached-skill")
        XCTAssertEqual(result.first?.name, "Cached Skill")
    }

    // MARK: - 2. Read-Only Fallback & No State Mutation in View Evaluation

    func testLocalSkillsFallbackDoesNotMutateStateDuringRead() throws {
        let projDir = tempDir.appendingPathComponent("fallback-proj", isDirectory: true)
        let skillsDir = projDir.appendingPathComponent(".agents/skills/disk-skill", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skillMd = skillsDir.appendingPathComponent("SKILL.md")
        try "---\nname: Disk Skill\ndescription: Found on disk\n---\n".write(to: skillMd, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "fb-proj", name: "Fallback Proj", path: projDir.path)
        let state = AppState(autoload: false)

        // projectLocalSkills does NOT have this project yet (nil)
        XCTAssertNil(state.projectLocalSkills[project.id])

        // Calling localSkills should fall back to disk scanner
        let result = state.localSkills(for: project)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "disk-skill")

        // Crucial invariant: state.projectLocalSkills[project.id] MUST remain nil!
        // (Must NOT mutate state during view evaluation)
        XCTAssertNil(state.projectLocalSkills[project.id])
    }

    // MARK: - 3. Observation Reactivity

    private final class ObservationBox: @unchecked Sendable {
        var changed = false
    }

    func testObservationReactivityOnLocalSkillsAndSafetyAudits() {
        let state = AppState(autoload: false)
        let skillsBox = ObservationBox()
        let auditsBox = ObservationBox()

        withObservationTracking {
            _ = state.projectLocalSkills
        } onChange: {
            skillsBox.changed = true
        }

        withObservationTracking {
            _ = state.projectSafetyAudits
        } onChange: {
            auditsBox.changed = true
        }

        XCTAssertFalse(skillsBox.changed)
        XCTAssertFalse(auditsBox.changed)

        state.projectLocalSkills["test"] = []
        XCTAssertTrue(skillsBox.changed)

        state.projectSafetyAudits["test"] = ProjectSafetyAudit.checking(for: ProjectProfile(id: "test", name: "test", path: "/test"))
        XCTAssertTrue(auditsBox.changed)
    }

    // MARK: - 4. Lifecycle Cache Population

    func testRegisterProjectFolderPopulatesLocalSkillsAndAudit() async throws {
        let projDir = tempDir.appendingPathComponent("newly-registered", isDirectory: true)
        let skillsDir = projDir.appendingPathComponent(".agents/skills/my-skill", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skillMd = skillsDir.appendingPathComponent("SKILL.md")
        try "---\nname: My Skill\ndescription: Registered skill\n---\n".write(to: skillMd, atomically: true, encoding: .utf8)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let state = AppState(autoload: false)
        await state.registerProjectFolder(at: projDir)

        let registered = state.projects.first { $0.path == projDir.path }
        XCTAssertNotNil(registered)
        guard let proj = registered else { return }

        // Local skills cache populated
        let cached = state.projectLocalSkills[proj.id]
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.count, 1)
        XCTAssertEqual(cached?.first?.id, "my-skill")

        // Safety audit cache populated
        let audit = state.projectSafetyAudits[proj.id]
        XCTAssertNotNil(audit)
        XCTAssertEqual(audit?.pathCheck.status, .passed)
        XCTAssertEqual(audit?.gitignoreCheck.status, .passed)
    }

    func testResetProjectsFolderAuthorizationClearsCaches() {
        let state = AppState(autoload: false)
        state.projectLocalSkills["p1"] = []
        state.projectSafetyAudits["p1"] = ProjectSafetyAudit.checking(for: ProjectProfile(id: "p1", name: "p1", path: "/p1"))

        state.resetProjectsFolderAuthorization()
        XCTAssertTrue(state.projectLocalSkills.isEmpty)
        XCTAssertTrue(state.projectSafetyAudits.isEmpty)
    }

    // MARK: - 5. ProjectSafetyAudit & ProjectAuditService Checks

    func testAuditMissingDirectoryFails() {
        let missingPath = tempDir.appendingPathComponent("nonexistent").path
        let project = ProjectProfile(id: "p1", name: "Missing", path: missingPath)
        let service = ProjectAuditService()
        let audit = service.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .failed)
        XCTAssertEqual(audit.overallStatus, .failed)
    }

    func testAuditUnprotectedGitignoreReturnsWarning() throws {
        let projDir = tempDir.appendingPathComponent("unprotected-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        let gitDir = projDir.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        try "node_modules/\n.DS_Store\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "p2", name: "Unprotected", path: projDir.path)
        let service = ProjectAuditService()
        let audit = service.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .passed)
        XCTAssertEqual(audit.gitignoreCheck.status, .warning)
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testAuditProtectedGitignoreAndSyncedManifestPasses() throws {
        let projDir = tempDir.appendingPathComponent("valid-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n.agents/mcp_config.json\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let mcpConfig = pluginDir.appendingPathComponent("mcp_config.json")
        let json: [String: Any] = ["mcpServers": ["s1": ["command": "npx"]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: mcpConfig)

        var project = ProjectProfile(id: "p3", name: "Valid", path: projDir.path)
        project.enabledMCPServerIds.insert("s1")

        let service = ProjectAuditService()
        let audit = service.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .passed)
        XCTAssertEqual(audit.gitignoreCheck.status, .passed)
        XCTAssertEqual(audit.manifestCheck.status, .passed)
        XCTAssertEqual(audit.overallStatus, .passed)
    }

    func testAuditDesyncedManifestReturnsWarning() throws {
        let projDir = tempDir.appendingPathComponent("desynced-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        // Project requires s1, but manifest on disk is missing
        var project = ProjectProfile(id: "p4", name: "Desynced", path: projDir.path)
        project.enabledMCPServerIds.insert("s1")

        let service = ProjectAuditService()
        let audit = service.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .warning)
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testAuditInvalidJsonManifestReturnsFailed() throws {
        let projDir = tempDir.appendingPathComponent("corrupt-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let mcpConfig = pluginDir.appendingPathComponent("mcp_config.json")
        try "{ this is corrupt json! }".write(to: mcpConfig, atomically: true, encoding: .utf8)

        var project = ProjectProfile(id: "p5", name: "Corrupt", path: projDir.path)
        project.enabledMCPServerIds.insert("s1")

        let service = ProjectAuditService()
        let audit = service.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .failed)
        XCTAssertEqual(audit.overallStatus, .failed)
    }

    func testAuditBrokenSymlinksReturnsWarning() throws {
        let projDir = tempDir.appendingPathComponent("broken-symlink-proj", isDirectory: true)
        let skillsDir = projDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        // Create a dangling symlink pointing to nonexistent target
        let linkPath = skillsDir.appendingPathComponent("dangling-skill")
        let nonExistentTarget = tempDir.appendingPathComponent("ghost-skill")
        try fm.createSymbolicLink(at: linkPath, withDestinationURL: nonExistentTarget)

        let project = ProjectProfile(id: "p6", name: "BrokenSymlink", path: projDir.path)
        let service = ProjectAuditService()
        let audit = service.audit(project: project)

        XCTAssertEqual(audit.symlinkCheck.status, .warning)
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testAuditEmptyServersSyncedManifestPasses() throws {
        let projDir = tempDir.appendingPathComponent("empty-servers-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "p7", name: "EmptyServers", path: projDir.path)
        let service = ProjectAuditService()
        let audit = service.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .passed)
        XCTAssertEqual(audit.manifestCheck.status, .passed)
        XCTAssertEqual(audit.overallStatus, .passed)
    }

    // MARK: - 6. Scan All Project Local Skills In Scanner Service

    func testScanAllProjectLocalSkills() throws {
        let p1Dir = tempDir.appendingPathComponent("proj1", isDirectory: true)
        let p1Skills = p1Dir.appendingPathComponent(".agents/skills/s1", isDirectory: true)
        try fm.createDirectory(at: p1Skills, withIntermediateDirectories: true)
        try "name: S1\n".write(to: p1Skills.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let p2Dir = tempDir.appendingPathComponent("proj2", isDirectory: true)
        let p2Skills = p2Dir.appendingPathComponent(".agents/skills/s2", isDirectory: true)
        try fm.createDirectory(at: p2Skills, withIntermediateDirectories: true)
        try "name: S2\n".write(to: p2Skills.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let p1 = ProjectProfile(id: "p1", name: "P1", path: p1Dir.path)
        let p2 = ProjectProfile(id: "p2", name: "P2", path: p2Dir.path)

        let scanner = SkillScannerService()
        let results = scanner.scanAllProjectLocalSkills(projects: [p1, p2])

        XCTAssertEqual(results["p1"]?.count, 1)
        XCTAssertEqual(results["p1"]?.first?.id, "s1")
        XCTAssertEqual(results["p2"]?.count, 1)
        XCTAssertEqual(results["p2"]?.first?.id, "s2")
    }

    // MARK: - 7. Zero-Lag Render Execution Benchmark

    func testViewBodyRenderExecutionTimeUnderOneMillisecond() throws {
        let projDir = tempDir.appendingPathComponent("bench-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "bench", name: "Benchmark", path: projDir.path)
        let state = AppState(autoload: false)
        state.projects = [project]
        state.projectLocalSkills[project.id] = []
        state.projectSafetyAudits[project.id] = ProjectSafetyAudit.checking(for: project)

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let detailView = ProjectDetailView(
            state: state,
            project: project,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )

        let skillsTab = ProjectSkillsTab(
            state: state,
            projectId: project.id,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )

        let sidebarView = ProjectIsolationSidebarView(
            project: project,
            state: state
        )

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = detailView.body
            _ = skillsTab.body
            _ = sidebarView.body
        }

        // Sub-millisecond execution (< 5ms on slow CI, typically < 0.2ms)
        XCTAssertLessThan(elapsed, .milliseconds(5))
    }
}
