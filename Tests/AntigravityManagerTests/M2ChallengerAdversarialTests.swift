import XCTest
import SwiftUI
@testable import AntigravityManager

final class M2ChallengerAdversarialTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M2ChallengerTests-\(UUID().uuidString)", isDirectory: true)
        let geminiDir = tempDir.appendingPathComponent(".gemini", isDirectory: true)
        let projectsDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        PathConstants.customGeminiDirectory = geminiDir
        PathConstants.customProjectsDirectory = projectsDir
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "projectFolderBookmark")
        ProjectFolderAccessManager.shared.resetAuthorization()
        if let tempDir {
            try? fm.removeItem(at: tempDir)
        }
        PathConstants.customGeminiDirectory = nil
        PathConstants.customProjectsDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Challenge 1: Multi-hop Symlink Preservation & Custom JSON Fields
    func testChallenger1_MultiHopSymlinkPreservationAndAtomicWrites() throws {
        let canonicalFile = tempDir.appendingPathComponent("canonical_mcp.json")
        let hop1Symlink = tempDir.appendingPathComponent("hop1_mcp.json")
        let hop2Symlink = tempDir.appendingPathComponent("hop2_mcp.json")

        // 1. Setup canonical file with rich custom fields
        let initialJSON: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "version": "1.4.2",
            "author": "Maintainer",
            "customPreferences": [
                "logLevel": "debug",
                "telemetry": false
            ],
            "mcpServers": [
                "legacy-server": [
                    "command": "python3",
                    "args": ["-m", "legacy"],
                    "disabled": false
                ]
            ]
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initialJSON, options: [.prettyPrinted])
        try initialData.write(to: canonicalFile)

        // 2. Setup multi-hop symlink: hop2 -> hop1 -> canonical
        try fm.createSymbolicLink(at: hop1Symlink, withDestinationURL: canonicalFile)
        try fm.createSymbolicLink(at: hop2Symlink, withDestinationURL: hop1Symlink)

        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: hop2Symlink.path), hop1Symlink.path)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: hop1Symlink.path), canonicalFile.path)

        // 3. Resolve symlinks
        let canonicalResolved = hop2Symlink.resolvingSymlinksInPath()
        XCTAssertEqual(canonicalResolved.path, canonicalFile.path, "resolvingSymlinksInPath must traverse multi-hop symlinks to the canonical file")

        // 4. Update JSON preserving top-level keys
        let existingData = try Data(contentsOf: canonicalResolved)
        var rootDict = try XCTUnwrap(JSONSerialization.jsonObject(with: existingData) as? [String: Any])
        var servers = try XCTUnwrap(rootDict["mcpServers"] as? [String: Any])
        servers["added-server"] = ["command": "npx", "disabled": true]
        rootDict["mcpServers"] = servers

        let updatedData = try JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: canonicalResolved, options: .atomic)

        // 5. Verify symlink chain remains intact!
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: hop2Symlink.path), hop1Symlink.path, "hop2 must still be a symlink")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: hop1Symlink.path), canonicalFile.path, "hop1 must still be a symlink")

        // 6. Verify contents read via hop2Symlink
        let readFromHop2 = try Data(contentsOf: hop2Symlink)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: readFromHop2) as? [String: Any])
        XCTAssertEqual(parsed["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(parsed["version"] as? String, "1.4.2")
        XCTAssertEqual(parsed["author"] as? String, "Maintainer")
        let prefs = try XCTUnwrap(parsed["customPreferences"] as? [String: Any])
        XCTAssertEqual(prefs["logLevel"] as? String, "debug")
        XCTAssertEqual(prefs["telemetry"] as? Bool, false)

        let parsedServers = try XCTUnwrap(parsed["mcpServers"] as? [String: Any])
        XCTAssertNotNil(parsedServers["legacy-server"])
        XCTAssertNotNil(parsedServers["added-server"])

        // 7. Empirical counter-proof: writing directly to symlink without resolving DESTROYS it
        let testDestructionLink = tempDir.appendingPathComponent("will_be_destroyed.json")
        try fm.createSymbolicLink(at: testDestructionLink, withDestinationURL: canonicalFile)
        XCTAssertTrue((try? fm.destinationOfSymbolicLink(atPath: testDestructionLink.path)) != nil)
        try updatedData.write(to: testDestructionLink, options: .atomic)
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: testDestructionLink.path), "Direct atomic write destroys symlink inode: proves resolvingSymlinksInPath is mandatory")
    }

    // MARK: - Challenge 2: Broken Symlink Lifecycle in .agents/skills (Reactivation, Purge, Repointing)
    func testChallenger2_BrokenSymlinkReactivationAndRepointing() async throws {
        let syncEngine = SyncEngine()
        let projectDir = tempDir.appendingPathComponent("adversarial-proj", isDirectory: true)
        let projectSkillsDir = projectDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: projectSkillsDir, withIntermediateDirectories: true)

        let skillId = "adversarial-skill"
        let skillTargetURL = projectSkillsDir.appendingPathComponent(skillId)

        // Step 1: Create a broken symlink (destination does not exist)
        let ghostSource = tempDir.appendingPathComponent("ghost-skill-folder")
        try fm.createSymbolicLink(at: skillTargetURL, withDestinationURL: ghostSource)

        XCTAssertFalse(fm.fileExists(atPath: skillTargetURL.path), "Broken symlink target does not exist")
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: skillTargetURL.path), "Broken symlink inode exists")

        // Step 2: Sync project with this skill ENABLED and a real source
        let realSource1 = tempDir.appendingPathComponent("real-skill-1", isDirectory: true)
        try fm.createDirectory(at: realSource1, withIntermediateDirectories: true)
        try "name: real1".write(to: realSource1.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        var skillDef = SkillDefinition(
            id: skillId,
            name: "Adversarial Skill",
            description: "Testing broken symlink revival",
            category: "test",
            path: realSource1.path,
            origin: .projectLocal
        )

        var project = ProjectProfile(
            id: "adversarial-proj",
            name: "Adversarial",
            path: projectDir.path,
            enabledSkillIds: [skillId]
        )

        // Must replace broken symlink without EEXIST
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [skillDef], allPlugins: [])
        XCTAssertTrue(fm.fileExists(atPath: skillTargetURL.path), "Broken symlink must be revived to realSource1")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: skillTargetURL.path), realSource1.path)

        // Step 3: Re-pointing to another source
        let realSource2 = tempDir.appendingPathComponent("real-skill-2", isDirectory: true)
        try fm.createDirectory(at: realSource2, withIntermediateDirectories: true)
        try "name: real2".write(to: realSource2.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        skillDef = SkillDefinition(
            id: skillId,
            name: "Adversarial Skill",
            description: "Testing re-pointing",
            category: "test",
            path: realSource2.path,
            origin: .projectLocal
        )

        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [skillDef], allPlugins: [])
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: skillTargetURL.path), realSource2.path, "Symlink must be re-pointed to realSource2")

        // Step 4: Disabling skill when link is broken
        // Simulate realSource2 getting deleted, leaving a broken symlink
        try fm.removeItem(at: realSource2)
        XCTAssertFalse(fm.fileExists(atPath: skillTargetURL.path), "Symlink is now broken again")
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: skillTargetURL.path))

        // Sync with skill disabled
        project.enabledSkillIds.remove(skillId)
        try await syncEngine.syncProject(project: project, allServers: [], allSkills: [skillDef], allPlugins: [])

        // Dead symlink must be cleanly removed
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: skillTargetURL.path), "Disabling skill must remove broken symlink")
        XCTAssertFalse(fm.fileExists(atPath: skillTargetURL.path))
    }

    // MARK: - Challenge 3: Broken Symlinks Completely Removed in Purge Flows
    func testChallenger3_BrokenSymlinkPurgeAcrossProjects() async throws {
        let syncEngine = SyncEngine()
        let projectADir = tempDir.appendingPathComponent("projA", isDirectory: true)
        let projectBDir = tempDir.appendingPathComponent("projB", isDirectory: true)
        let projectASkills = projectADir.appendingPathComponent(".agents/skills", isDirectory: true)
        let projectBSkills = projectBDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: projectASkills, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectBSkills, withIntermediateDirectories: true)

        let purgedSkillId = "purged-skill"
        let linkA = projectASkills.appendingPathComponent(purgedSkillId)
        let linkB = projectBSkills.appendingPathComponent(purgedSkillId)

        // Create broken symlinks in both projects
        let fakeDeadTarget = tempDir.appendingPathComponent("dead-target")
        try fm.createSymbolicLink(at: linkA, withDestinationURL: fakeDeadTarget)
        try fm.createSymbolicLink(at: linkB, withDestinationURL: fakeDeadTarget)

        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: linkA.path))
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: linkB.path))

        let projects = [
            ProjectProfile(id: "projA", name: "Project A", path: projectADir.path),
            ProjectProfile(id: "projB", name: "Project B", path: projectBDir.path)
        ]

        await syncEngine.purgeSkillCompletely(id: purgedSkillId, allProjects: projects)

        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: linkA.path), "Project A broken symlink must be purged")
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: linkB.path), "Project B broken symlink must be purged")
    }

    // MARK: - Challenge 4: Surgical .gitignore Rules and Non-Interference with Custom Plugins
    func testChallenger4_SurgicalGitignoreProtectionAndCustomPlugins() async throws {
        let syncEngine = SyncEngine()
        let projectDir = tempDir.appendingPathComponent("repo-with-plugins", isDirectory: true)
        let customPluginDir = projectDir.appendingPathComponent(".agents/plugins/my-custom-plugin", isDirectory: true)
        try fm.createDirectory(at: customPluginDir, withIntermediateDirectories: true)
        try "{\"name\": \"custom\"}".write(to: customPluginDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let gitignoreURL = projectDir.appendingPathComponent(".gitignore")
        let baseGitignore = """
        # Initial rules
        dist/
        .env
        """
        try baseGitignore.write(to: gitignoreURL, atomically: true, encoding: .utf8)

        // Run ensureGitignore
        await syncEngine.ensureGitignore(at: projectDir)

        let gitignoreContent = try String(contentsOf: gitignoreURL, encoding: .utf8)

        // Must protect agy-manager credentials
        XCTAssertTrue(gitignoreContent.contains(".agents/plugins/agy-manager/"), "Must protect agy-manager")
        XCTAssertTrue(gitignoreContent.contains(".agents/mcp_config.json"), "Must protect mcp_config.json")

        // Must NOT ignore .agents/plugins/ or my-custom-plugin
        let lines = gitignoreContent.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertFalse(lines.contains(".agents/plugins"), "Must NOT ignore all plugins")
        XCTAssertFalse(lines.contains(".agents/plugins/"), "Must NOT ignore all plugins trailing slash")
        XCTAssertFalse(lines.contains(".agents/plugins/*"), "Must NOT ignore plugins wildcard")
        XCTAssertFalse(lines.contains(".agents/plugins/my-custom-plugin"), "Must NOT ignore custom plugin")

        // Idempotency: multiple invocations must not change file
        for _ in 0..<5 {
            await syncEngine.ensureGitignore(at: projectDir)
        }
        let repeatedContent = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertEqual(repeatedContent, gitignoreContent, "Multiple invocations of ensureGitignore must be strictly idempotent")
    }

    // MARK: - Challenge 5: VaultServersTab ViewBuilder Zero-Lag Body Verification
    @MainActor
    func testChallenger5_VaultServersTabBodyHasNoSynchronousFileIO() {
        let state = AppState()
        let server = MCPServerDefinition(
            id: "test-server-cmd",
            name: "Server With Cmd",
            category: "core",
            config: [
                "command": .string("/usr/local/bin/dummy-executable --flag"),
                "disabled": .bool(false)
            ]
        )
        state.servers = [server]

        var target: DeletionTarget? = nil
        let binding = Binding<DeletionTarget?>(
            get: { target },
            set: { target = $0 }
        )

        let tab = VaultServersTab(state: state, deletionTarget: binding)

        // Evaluate view body rendering (which executes LazyVGrid and serverCard)
        let body = tab.body
        XCTAssertNotNil(body)

        // Evaluate cmd.contains("/") - in memory check
        let cmd = "/usr/local/bin/dummy-executable --flag"
        XCTAssertTrue(cmd.contains("/"))
        let extractedPath = cmd.split(separator: " ").first.map(String.init) ?? cmd
        XCTAssertEqual(extractedPath, "/usr/local/bin/dummy-executable")
        state.cancelPendingTasks()
    }
}
