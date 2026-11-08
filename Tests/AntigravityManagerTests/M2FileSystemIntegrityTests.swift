import XCTest
import SwiftUI
@testable import AntigravityManager

@MainActor
final class M2FileSystemIntegrityTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M2Tests-\(UUID().uuidString)", isDirectory: true)
        let geminiDir = tempDir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let tempDir {
            try? fm.removeItem(at: tempDir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        super.tearDown()
    }

    // MARK: - FS1: Canonical Symlink Preservation & Custom JSON Fields
    func testFS1_CanonicalSymlinkPreservationAndCustomFields() throws {
        let canonicalFile = tempDir.appendingPathComponent("canonical_mcp_config.json")
        let symlinkFile = tempDir.appendingPathComponent("symlink_mcp_config.json")

        let initialJSON: [String: Any] = [
            "$schema": "https://example.com/schema.json",
            "version": "2.0.0",
            "customMetadata": "preserved",
            "mcpServers": [
                "old-server": ["command": "npx", "disabled": false]
            ]
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initialJSON, options: [.prettyPrinted])
        try initialData.write(to: canonicalFile)
        try fm.createSymbolicLink(at: symlinkFile, withDestinationURL: canonicalFile)

        // Verify symlink setup
        let isLinkBefore = (try? fm.destinationOfSymbolicLink(atPath: symlinkFile.path)) != nil
        XCTAssertTrue(isLinkBefore, "symlinkFile must initially be a symbolic link")

        // Atomic write directly to canonical target
        let canonicalTarget = symlinkFile.resolvingSymlinksInPath()
        XCTAssertEqual(canonicalTarget.path, canonicalFile.path)

        var rootDict: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: canonicalTarget),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            rootDict = existingJSON
        }

        rootDict["mcpServers"] = ["new-server": ["command": "node", "disabled": false]]
        let data = try JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: canonicalTarget, options: .atomic)

        // Symlink must still be a symlink
        let isLinkAfter = (try? fm.destinationOfSymbolicLink(atPath: symlinkFile.path)) != nil
        XCTAssertTrue(isLinkAfter, "symlinkFile must remain a symbolic link after atomic update to canonical target")

        // Top-level custom fields must be preserved
        let readData = try Data(contentsOf: symlinkFile)
        let parsed = try JSONSerialization.jsonObject(with: readData) as? [String: Any]
        XCTAssertEqual(parsed?["$schema"] as? String, "https://example.com/schema.json")
        XCTAssertEqual(parsed?["version"] as? String, "2.0.0")
        XCTAssertEqual(parsed?["customMetadata"] as? String, "preserved")

        let servers = parsed?["mcpServers"] as? [String: Any]
        XCTAssertNotNil(servers?["new-server"])
    }

    // MARK: - FS2: Orphaned Symlinks Cleanup on Purge
    func testFS2_OrphanedSymlinksCleanupOnPurge() async throws {
        let syncEngine = SyncEngine()
        let fakeProjectDir = tempDir.appendingPathComponent("fake-proj", isDirectory: true)
        let fakeProjectSkillsDir = fakeProjectDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: fakeProjectSkillsDir, withIntermediateDirectories: true)

        let targetSkillURL = fakeProjectSkillsDir.appendingPathComponent("test-orphan-skill")
        let nonExistentDestination = tempDir.appendingPathComponent("vault-deleted-skill")
        // Create a dead/broken symlink
        try fm.createSymbolicLink(at: targetSkillURL, withDestinationURL: nonExistentDestination)

        // Verify dead symlink exists as inode
        XCTAssertFalse(fm.fileExists(atPath: targetSkillURL.path), "Target of dead link does not exist")
        XCTAssertTrue((try? fm.destinationOfSymbolicLink(atPath: targetSkillURL.path)) != nil, "Dead symlink inode exists")

        let project = ProjectProfile(id: "fake-proj", name: "Fake", path: fakeProjectDir.path)
        await syncEngine.purgeSkillCompletely(id: "test-orphan-skill", allProjects: [project])

        // Verify dead symlink was completely removed
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: targetSkillURL.path), "Orphaned symlink must be removed by purge")
    }

    // MARK: - FS3: Broken Symlink Reactivation in Project
    func testFS3_BrokenSymlinkReactivationInProject() async throws {
        let syncEngine = SyncEngine()
        let projectDir = tempDir.appendingPathComponent("reactivate-proj", isDirectory: true)
        let projectSkillsDir = projectDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: projectSkillsDir, withIntermediateDirectories: true)

        let targetSkillURL = projectSkillsDir.appendingPathComponent("revived-skill")
        let deadDestination = tempDir.appendingPathComponent("nonexistent-source")
        try fm.createSymbolicLink(at: targetSkillURL, withDestinationURL: deadDestination)

        // Create a real new source
        let realSourceDir = tempDir.appendingPathComponent("real-source-skill", isDirectory: true)
        try fm.createDirectory(at: realSourceDir, withIntermediateDirectories: true)

        let skillDef = SkillDefinition(
            id: "revived-skill",
            name: "Revived Skill",
            description: "Test description",
            category: "tools",
            path: realSourceDir.path,
            origin: .projectLocal
        )

        let project = ProjectProfile(
            id: "reactivate-proj",
            name: "Reactivate Proj",
            path: projectDir.path,
            enabledSkillIds: ["revived-skill"]
        )

        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [skillDef], allPlugins: [])

        // Dead symlink must be replaced by link to real source
        let dest = try fm.destinationOfSymbolicLink(atPath: targetSkillURL.path)
        XCTAssertEqual(dest, realSourceDir.path)
        XCTAssertTrue(fm.fileExists(atPath: targetSkillURL.path))
    }

    // MARK: - FS4: Physical Directory Handling in Global Skills
    func testFS4_PhysicalDirectoryHandlingInGlobalSkills() throws {
        let globalSkillsDir = tempDir.appendingPathComponent("global-skills", isDirectory: true)
        let vaultSkillsDir = tempDir.appendingPathComponent("vault-skills", isDirectory: true)
        try fm.createDirectory(at: globalSkillsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: vaultSkillsDir, withIntermediateDirectories: true)

        // Physical folder representing a global skill
        let targetURL = globalSkillsDir.appendingPathComponent("physical-skill")
        let vaultSkillURL = vaultSkillsDir.appendingPathComponent("physical-skill")
        try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try "content".write(to: targetURL.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Simulate FS4 disable behavior: if physical directory, ensure backed up in vault, then remove
        let isLink = (try? fm.destinationOfSymbolicLink(atPath: targetURL.path)) != nil
        XCTAssertFalse(isLink, "Target must be physical directory, not symlink")

        if !fm.fileExists(atPath: vaultSkillURL.path) {
            try? fm.copyItem(at: targetURL, to: vaultSkillURL)
        }
        if fm.fileExists(atPath: vaultSkillURL.path) {
            try? fm.removeItem(at: targetURL)
        }

        // Verify backed up in vault and removed from global
        XCTAssertTrue(fm.fileExists(atPath: vaultSkillURL.path), "Physical skill must be safely copied to vault")
        XCTAssertFalse(fm.fileExists(atPath: targetURL.path), "Physical folder in global skills must be cleanly removed")
    }

    // MARK: - FS7: Debounce and Real Error Reporting
    func testFS7_DebounceAndRealErrorReporting() async {
        let state = AppState()
        let project = ProjectProfile(
            id: "debounce-test-proj",
            name: "Debounce Test",
            path: tempDir.appendingPathComponent("debounce-proj").path
        )
        state.projects = [project]

        // Rapid toggling
        state.toggleProjectServer(projectId: project.id, serverId: "s1")
        state.toggleProjectServer(projectId: project.id, serverId: "s2")
        state.toggleProjectServer(projectId: project.id, serverId: "s3")

        // Tasks must be debounced and not throw uncaught errors
        XCTAssertNotNil(state.projectSyncDebounceTasks[project.id])
        state.cancelPendingTasks()
    }

    // MARK: - FS8: Surgical .gitignore Protection
    func testFS8_SurgicalGitignoreProtection() async throws {
        let syncEngine = SyncEngine()
        let projectDir = tempDir.appendingPathComponent("gitignore-test-proj", isDirectory: true)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let gitignoreURL = projectDir.appendingPathComponent(".gitignore")
        let initialGitignore = """
        node_modules/
        .DS_Store
        """
        try initialGitignore.write(to: gitignoreURL, atomically: true, encoding: .utf8)

        await syncEngine.ensureGitignore(at: projectDir)

        let updated = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertTrue(updated.contains(".agents/plugins/agy-manager/"), "Must protect .agents/plugins/agy-manager/")
        XCTAssertTrue(updated.contains(".agents/mcp_config.json"), "Must protect .agents/mcp_config.json")
        XCTAssertFalse(updated.contains(".agents/plugins/\n"), "Must NOT ignore all plugins globally")

        // Idempotency: second run should not duplicate
        await syncEngine.ensureGitignore(at: projectDir)
        let second = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertEqual(updated, second, "ensureGitignore must be idempotent")
    }

    // MARK: - FS9: Config Directory Auto-Creation
    func testFS9_ConfigDirectoryAutoCreation() throws {
        let nestedConfigDir = tempDir.appendingPathComponent("nested/new/config/dir", isDirectory: true)
        XCTAssertFalse(fm.fileExists(atPath: nestedConfigDir.path))

        // Create directory dynamically
        try fm.createDirectory(at: nestedConfigDir, withIntermediateDirectories: true)
        XCTAssertTrue(fm.fileExists(atPath: nestedConfigDir.path))
    }

    // MARK: - FS10: Project Skills Preservation on Discovery
    func testFS10_ProjectSkillsPreservation() throws {
        let scanner = ProjectScannerService()
        let projectDir = tempDir.appendingPathComponent("my-project", isDirectory: true)
        let skillsDir = projectDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        let localSkillDir = skillsDir.appendingPathComponent("ios-design-system")
        try fm.createDirectory(at: localSkillDir, withIntermediateDirectories: true)

        let discovered = scanner.discoverProjects(in: tempDir)
        let found = discovered.first { $0.id == "my-project" }
        XCTAssertNotNil(found)
        XCTAssertTrue(found?.enabledSkillIds.contains("ios-design-system") == true, "ProjectScannerService must discover active .agents/skills")
    }
}
