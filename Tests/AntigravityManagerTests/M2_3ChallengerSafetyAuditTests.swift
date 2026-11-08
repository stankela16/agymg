import XCTest
import SwiftUI
@testable import AntigravityManager

@MainActor
final class M2_3ChallengerSafetyAuditTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M2_3ChallengerTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Challenge 1: Path Non-Existence and Malformation (Must flag .failed)

    func testChallenger1_PathDoesNotExist_FlagsFailedAndCascades() {
        let nonexistentPath = tempDir.appendingPathComponent("phantom-workspace-\(UUID().uuidString)").path
        let project = ProjectProfile(id: "phantom-proj", name: "Phantom", path: nonexistentPath)
        let auditService = ProjectAuditService()

        let audit = auditService.audit(project: project)

        // Path check must be .failed
        XCTAssertEqual(audit.pathCheck.status, .failed)
        XCTAssertTrue(audit.pathCheck.detail.contains("Path does not exist on disk"))
        XCTAssertEqual(audit.overallStatus, .failed)

        // Cascading checks: gitignore, manifest, symlinks must all report .failed
        XCTAssertEqual(audit.gitignoreCheck.status, .failed)
        XCTAssertEqual(audit.gitignoreCheck.detail, "Project directory unavailable")
        XCTAssertEqual(audit.manifestCheck.status, .failed)
        XCTAssertEqual(audit.manifestCheck.detail, "Project directory unavailable")
        XCTAssertEqual(audit.symlinkCheck.status, .failed)
        XCTAssertEqual(audit.symlinkCheck.detail, "Project directory unavailable")
    }

    func testChallenger1_PathIsRegularFileInsteadOfDirectory_FlagsFailed() throws {
        let regularFilePath = tempDir.appendingPathComponent("regular_file.txt").path
        try "Not a directory".write(toFile: regularFilePath, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "file-proj", name: "FileNotDir", path: regularFilePath)
        let auditService = ProjectAuditService()

        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .failed)
        XCTAssertEqual(audit.pathCheck.detail, "Path is not a directory")
        XCTAssertEqual(audit.overallStatus, .failed)
    }

    func testChallenger1_PathIsEmptyString_FlagsFailed() {
        let project = ProjectProfile(id: "empty-path-proj", name: "EmptyPath", path: "")
        let auditService = ProjectAuditService()

        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .failed)
        XCTAssertEqual(audit.overallStatus, .failed)
    }

    func testChallenger1_DirectoryDeletedAtRuntime_TransitionsToFailed() throws {
        let projDir = tempDir.appendingPathComponent("ephemeral-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let project = ProjectProfile(id: "ephemeral", name: "Ephemeral", path: projDir.path)
        let auditService = ProjectAuditService()

        let initialAudit = auditService.audit(project: project)
        XCTAssertEqual(initialAudit.pathCheck.status, .passed)

        // Delete from disk
        try fm.removeItem(at: projDir)
        XCTAssertFalse(fm.fileExists(atPath: projDir.path))

        let subsequentAudit = auditService.audit(project: project)
        XCTAssertEqual(subsequentAudit.pathCheck.status, .failed)
        XCTAssertEqual(subsequentAudit.overallStatus, .failed)
    }

    // MARK: - Challenge 2: .gitignore Protection Checks (Must flag .warning or .passed)

    func testChallenger2_GitRepoWithoutGitignore_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("git-repo-no-ignore", isDirectory: true)
        let gitDir = projDir.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let project = ProjectProfile(id: "git-no-ignore", name: "GitNoIgnore", path: projDir.path)
        let auditService = ProjectAuditService()

        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .passed)
        XCTAssertEqual(audit.gitignoreCheck.status, .warning)
        XCTAssertTrue(audit.gitignoreCheck.detail.contains("Git repository has no .gitignore"))
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testChallenger2_NonGitFolderWithoutGitignore_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("plain-folder-no-ignore", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let project = ProjectProfile(id: "plain-no-ignore", name: "PlainNoIgnore", path: projDir.path)
        let auditService = ProjectAuditService()

        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.pathCheck.status, .passed)
        XCTAssertEqual(audit.gitignoreCheck.status, .warning)
        XCTAssertTrue(audit.gitignoreCheck.detail.contains("recommended before committing"))
    }

    func testChallenger2_GitignoreWithUnrelatedOrEmptyRules_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("unrelated-rules-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        let content = """
        # Comments
        node_modules/
        .DS_Store
        build/
        *.log
        """
        try content.write(to: gitignore, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "unrelated-proj", name: "Unrelated", path: projDir.path)
        let auditService = ProjectAuditService()

        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.gitignoreCheck.status, .warning)
        XCTAssertTrue(audit.gitignoreCheck.detail.contains("Missing rule for .agents/plugins/agy-manager"))
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testChallenger2_GitignoreWithPartialOrCommentedRules_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("partial-rules-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        let content = """
        # .agents/plugins/agy-manager/
        plugins/agy-manager
        agy-manager
        .agents-other
        """
        try content.write(to: gitignore, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "partial-proj", name: "Partial", path: projDir.path)
        let auditService = ProjectAuditService()

        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.gitignoreCheck.status, .warning)
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testChallenger2_GitignoreValidRuleVariants_AllPass() throws {
        let validVariants: [String] = [
            ".agents",
            ".agents/",
            ".agents/*",
            "/.agents",
            "/.agents/",
            ".agents/plugins",
            ".agents/plugins/",
            ".agents/plugins/*",
            "/.agents/plugins/",
            ".agents/plugins/agy-manager",
            ".agents/plugins/agy-manager/",
            ".agents/plugins/agy-manager/*",
            "/.agents/plugins/agy-manager/",
            "   .agents/plugins/agy-manager/   " // Whitespace tolerance
        ]

        let auditService = ProjectAuditService()

        for (index, rule) in validVariants.enumerated() {
            let projDir = tempDir.appendingPathComponent("variant-proj-\(index)", isDirectory: true)
            try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

            let gitignore = projDir.appendingPathComponent(".gitignore")
            try "node_modules/\n\(rule)\n.DS_Store\n".write(to: gitignore, atomically: true, encoding: .utf8)

            let project = ProjectProfile(id: "variant-\(index)", name: "Variant \(index)", path: projDir.path)
            let item = auditService.auditGitignore(project: project)

            XCTAssertEqual(item.status, .passed, "Rule variant failed to pass: '\(rule)'")
            XCTAssertTrue(item.detail.contains(".gitignore protects"), "Detail mismatch for rule: '\(rule)'")
        }
    }

    // MARK: - Challenge 3: Runtime Manifest Missing, Corrupt, or Desynced

    func testChallenger3_ManifestMissingWhenServersExpected_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("missing-manifest-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        var project = ProjectProfile(id: "missing-manifest", name: "MissingManifest", path: projDir.path)
        project.enabledMCPServerIds = ["server-alpha"]

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .warning)
        XCTAssertTrue(audit.manifestCheck.detail.contains("does not exist on disk (sync required)"))
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testChallenger3_ManifestCorrupt_SyntaxError_FlagsFailed() throws {
        let projDir = tempDir.appendingPathComponent("corrupt-syntax-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = pluginDir.appendingPathComponent("mcp_config.json")
        try "{ \"mcpServers\": { unquoted_key: 123 }".write(to: manifest, atomically: true, encoding: .utf8)

        var project = ProjectProfile(id: "corrupt-syntax", name: "CorruptSyntax", path: projDir.path)
        project.enabledMCPServerIds = ["server-alpha"]

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .failed)
        XCTAssertTrue(audit.manifestCheck.detail.contains("invalid JSON"))
        XCTAssertEqual(audit.overallStatus, .failed)
    }

    func testChallenger3_ManifestCorrupt_SchemaTypeMismatch_FlagsFailed() throws {
        let projDir = tempDir.appendingPathComponent("corrupt-schema-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = pluginDir.appendingPathComponent("mcp_config.json")
        // "mcpServers" is an array or string instead of a dictionary
        try "{ \"mcpServers\": [\"not\", \"a\", \"dictionary\"] }".write(to: manifest, atomically: true, encoding: .utf8)

        var project = ProjectProfile(id: "corrupt-schema", name: "CorruptSchema", path: projDir.path)
        project.enabledMCPServerIds = ["server-alpha"]

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .failed)
        XCTAssertTrue(audit.manifestCheck.detail.contains("invalid JSON"))
        XCTAssertEqual(audit.overallStatus, .failed)
    }

    func testChallenger3_ManifestDesynced_MissingServerOnDisk_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("desync-missing-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = pluginDir.appendingPathComponent("mcp_config.json")
        let json: [String: Any] = [
            "mcpServers": [
                "server-alpha": ["command": "npx"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: manifest)

        var project = ProjectProfile(id: "desync-missing", name: "DesyncMissing", path: projDir.path)
        // Project expects server-alpha AND server-beta
        project.enabledMCPServerIds = ["server-alpha", "server-beta"]

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .warning)
        XCTAssertTrue(audit.manifestCheck.detail.contains("missing: server-beta"))
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testChallenger3_ManifestDesynced_ExtraServerOnDisk_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("desync-extra-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = pluginDir.appendingPathComponent("mcp_config.json")
        let json: [String: Any] = [
            "mcpServers": [
                "server-alpha": ["command": "npx"],
                "rogue-server": ["command": "bash"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: manifest)

        var project = ProjectProfile(id: "desync-extra", name: "DesyncExtra", path: projDir.path)
        project.enabledMCPServerIds = ["server-alpha"]

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .warning)
        XCTAssertTrue(audit.manifestCheck.detail.contains("extra: rogue-server"))
        XCTAssertEqual(audit.overallStatus, .warning)
    }

    func testChallenger3_ManifestDesynced_BothMissingAndExtra_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("desync-both-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = pluginDir.appendingPathComponent("mcp_config.json")
        let json: [String: Any] = [
            "mcpServers": [
                "server-disk-only": ["command": "npx"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: manifest)

        var project = ProjectProfile(id: "desync-both", name: "DesyncBoth", path: projDir.path)
        project.enabledMCPServerIds = ["server-project-only"]

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .warning)
        XCTAssertTrue(audit.manifestCheck.detail.contains("missing: server-project-only"))
        XCTAssertTrue(audit.manifestCheck.detail.contains("extra: server-disk-only"))
    }

    func testChallenger3_ManifestStale_EmptyProjectWithNonEmptyDiskManifest_FlagsWarning() throws {
        let projDir = tempDir.appendingPathComponent("stale-manifest-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = pluginDir.appendingPathComponent("mcp_config.json")
        let json: [String: Any] = [
            "mcpServers": [
                "old-server": ["command": "npx"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: manifest)

        let project = ProjectProfile(id: "stale-proj", name: "Stale", path: projDir.path, enabledMCPServerIds: [])

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .warning)
        XCTAssertTrue(audit.manifestCheck.detail.contains("Stale manifest contains 1 servers while profile is empty"))
    }

    func testChallenger3_ManifestSynced_BothEmptyOrMatching_Passes() throws {
        let projDir = tempDir.appendingPathComponent("synced-manifest-proj", isDirectory: true)
        let pluginDir = projDir.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = pluginDir.appendingPathComponent("mcp_config.json")
        let json: [String: Any] = [
            "mcpServers": [
                "s1": ["command": "npx"],
                "s2": ["command": "node"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: manifest)

        var project = ProjectProfile(id: "synced-proj", name: "Synced", path: projDir.path)
        project.enabledMCPServerIds = ["s1", "s2"]

        let auditService = ProjectAuditService()
        let audit = auditService.audit(project: project)

        XCTAssertEqual(audit.manifestCheck.status, .passed)
        XCTAssertTrue(audit.manifestCheck.detail.contains("Synchronized (2 servers valid)"))
    }

    // MARK: - Challenge 4: Dynamic UI Rendering & 1-Click Sync Remediation

    func testChallenger4_OverallStatusRollupPriority() {
        // 1. .failed takes precedence over everything
        let auditWithFailure = ProjectSafetyAudit(
            pathCheck: ProjectSafetyAudit.AuditItem(id: "1", title: "P", detail: "ok", status: .passed),
            gitignoreCheck: ProjectSafetyAudit.AuditItem(id: "2", title: "G", detail: "warn", status: .warning),
            manifestCheck: ProjectSafetyAudit.AuditItem(id: "3", title: "M", detail: "fail", status: .failed),
            symlinkCheck: ProjectSafetyAudit.AuditItem(id: "4", title: "S", detail: "check", status: .checking)
        )
        XCTAssertEqual(auditWithFailure.overallStatus, .failed)

        // 2. .warning takes precedence over .checking and .passed
        let auditWithWarning = ProjectSafetyAudit(
            pathCheck: ProjectSafetyAudit.AuditItem(id: "1", title: "P", detail: "ok", status: .passed),
            gitignoreCheck: ProjectSafetyAudit.AuditItem(id: "2", title: "G", detail: "warn", status: .warning),
            manifestCheck: ProjectSafetyAudit.AuditItem(id: "3", title: "M", detail: "check", status: .checking),
            symlinkCheck: ProjectSafetyAudit.AuditItem(id: "4", title: "S", detail: "ok", status: .passed)
        )
        XCTAssertEqual(auditWithWarning.overallStatus, .warning)

        // 3. .checking takes precedence over .passed
        let auditWithChecking = ProjectSafetyAudit(
            pathCheck: ProjectSafetyAudit.AuditItem(id: "1", title: "P", detail: "ok", status: .passed),
            gitignoreCheck: ProjectSafetyAudit.AuditItem(id: "2", title: "G", detail: "ok", status: .passed),
            manifestCheck: ProjectSafetyAudit.AuditItem(id: "3", title: "M", detail: "check", status: .checking),
            symlinkCheck: ProjectSafetyAudit.AuditItem(id: "4", title: "S", detail: "ok", status: .passed)
        )
        XCTAssertEqual(auditWithChecking.overallStatus, .checking)

        // 4. All passed -> .passed
        let auditAllPassed = ProjectSafetyAudit(
            pathCheck: ProjectSafetyAudit.AuditItem(id: "1", title: "P", detail: "ok", status: .passed),
            gitignoreCheck: ProjectSafetyAudit.AuditItem(id: "2", title: "G", detail: "ok", status: .passed),
            manifestCheck: ProjectSafetyAudit.AuditItem(id: "3", title: "M", detail: "ok", status: .passed),
            symlinkCheck: ProjectSafetyAudit.AuditItem(id: "4", title: "S", detail: "ok", status: .passed)
        )
        XCTAssertEqual(auditAllPassed.overallStatus, .passed)
    }

    func testChallenger4_OneClickSyncRemediation_CuresWarningToPassed() async throws {
        // Setup isolated project environment
        let projDir = tempDir.appendingPathComponent("remediation-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let geminiDir = tempDir.appendingPathComponent("remediation-gemini", isDirectory: true)
        let vaultDir = geminiDir.appendingPathComponent("manager-vault", isDirectory: true)
        try fm.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        PathConstants.customGeminiDirectory = geminiDir

        // 1. Initial flawed state: .gitignore has NO protection rule, and mcp_config.json is missing
        let gitignore = projDir.appendingPathComponent(".gitignore")
        try "node_modules/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let serverDef = MCPServerDefinition(
            id: "safe-server",
            name: "Safe Server",
            category: "Core",
            config: ["command": .string("npx")]
        )

        var project = ProjectProfile(id: "remed-proj", name: "Remediation", path: projDir.path)
        project.enabledMCPServerIds = ["safe-server"]

        let state = AppState(autoload: false)
        state.servers = [serverDef]
        state.projects = [project]

        // Initial safety audit must be .warning
        let initialAudit = state.projectAuditService.audit(project: project)
        state.projectSafetyAudits[project.id] = initialAudit

        XCTAssertEqual(state.safetyAudit(for: project).overallStatus, .warning)
        XCTAssertEqual(state.safetyAudit(for: project).gitignoreCheck.status, .warning)
        XCTAssertEqual(state.safetyAudit(for: project).manifestCheck.status, .warning)

        // Verify view body executes without errors in warning state
        let sidebarView = ProjectIsolationSidebarView(project: project, state: state)
        _ = sidebarView.body

        // 2. Perform 1-Click Remediation (what button 'Sync & Protect' triggers)
        await state.performProjectSync(projectId: project.id)

        // 3. Verify disk outcomes:
        // A) .gitignore now protects agy-manager
        let updatedGitignore = try String(contentsOf: gitignore, encoding: .utf8)
        XCTAssertTrue(updatedGitignore.contains(".agents/plugins/agy-manager/"), "Sync must protect agy-manager in .gitignore")
        XCTAssertTrue(updatedGitignore.contains(".agents/mcp_config.json"), "Sync must protect mcp_config.json in .gitignore")

        // B) mcp_config.json was generated and matches server
        let manifestURL = projDir.appendingPathComponent(".agents/plugins/agy-manager/mcp_config.json")
        XCTAssertTrue(fm.fileExists(atPath: manifestURL.path), "Manifest must be generated on disk")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifestJson = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let serversDict = try XCTUnwrap(manifestJson["mcpServers"] as? [String: Any])
        XCTAssertNotNil(serversDict["safe-server"])

        // 4. Verify in-memory state was automatically refreshed to .passed!
        let postSyncAudit = state.safetyAudit(for: project)
        XCTAssertEqual(postSyncAudit.gitignoreCheck.status, .passed)
        XCTAssertEqual(postSyncAudit.manifestCheck.status, .passed)
        XCTAssertEqual(postSyncAudit.pathCheck.status, .passed)
        XCTAssertEqual(postSyncAudit.overallStatus, .passed)

        // 5. Verify view body executes in passed state
        _ = sidebarView.body

        PathConstants.customGeminiDirectory = nil
        state.cancelPendingTasks()
    }
}
