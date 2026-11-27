import XCTest
@testable import AntigravityManager

final class ExternalAdoptionTests: XCTestCase {
    private let fm = FileManager.default
    private var sandbox: URL!
    private let vault = VaultService()

    override func setUp() {
        super.setUp()
        sandbox = fm.temporaryDirectory.appendingPathComponent("ExternalAdoptionTests_\(UUID().uuidString)", isDirectory: true)
        let gemini = sandbox.appendingPathComponent(".gemini", isDirectory: true)
        PathConstants.customGeminiDirectory = gemini
        for dir in [PathConstants.vaultSkillsDirectory, PathConstants.globalSkillsDirectory, PathConstants.claudeGlobalSkillsDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        try? fm.removeItem(at: sandbox)
        PathConstants.customGeminiDirectory = nil
        super.tearDown()
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private func makeSkill(named name: String, in directory: URL) throws {
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\n---\n".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func testServerAddedInClaudeIsConvertedAndEnabled() async throws {
        try writeJSON(["mcpServers": ["linear": ["type": "http", "url": "https://mcp.linear.app/mcp", "headersHelper": "/x.py"]]], to: PathConstants.claudeConfigFile)

        let adopted = await vault.adoptExternalChanges(projects: [])

        XCTAssertEqual(adopted.serverIds, ["linear"])
        let server = await vault.loadServers().first { $0.id == "linear" }
        XCTAssertEqual(server?.config["serverUrl"]?.stringValue, "https://mcp.linear.app/mcp")
        XCTAssertNil(server?.config["type"])
        XCTAssertNil(server?.config["headersHelper"])
        let selection = await vault.loadGlobalSelection()
        XCTAssertTrue(selection.enabledMCPServerIds.contains("linear"))
    }

    func testProjectScopedClaudeServerEnablesOnlyThatProject() async throws {
        let project = ProjectProfile(id: "demo", name: "demo", path: sandbox.appendingPathComponent("demo").path)
        try writeJSON(["projects": [project.path: ["mcpServers": ["tool": ["type": "stdio", "command": "tool"]]]]], to: PathConstants.claudeConfigFile)
        await vault.saveProjects([project])

        let adopted = await vault.adoptExternalChanges(projects: [project])

        XCTAssertEqual(adopted.projectIds, ["demo"])
        let selection = await vault.loadGlobalSelection()
        XCTAssertFalse(selection.enabledMCPServerIds.contains("tool"))
        let saved = try JSONDecoder().decode([ProjectProfile].self, from: Data(contentsOf: PathConstants.vaultProjectsFile))
        XCTAssertTrue(saved[0].enabledMCPServerIds.contains("tool"))
    }

    func testToggleInAntigravityWinsOverStaleClaudeEntry() async throws {
        await vault.saveServers([
            MCPServerDefinition(id: "on", config: ["command": .string("a")]),
            MCPServerDefinition(id: "off", config: ["command": .string("b")])
        ])
        await vault.saveGlobalSelection(GlobalSelection(enabledMCPServerIds: ["off"]))
        try writeJSON(["mcpServers": ["on": ["command": "a", "disabled": false], "off": ["command": "b", "disabled": true]]], to: PathConstants.globalMCPConfigFile)
        try writeJSON(["mcpServers": ["off": ["type": "stdio", "command": "b"]]], to: PathConstants.claudeConfigFile)

        _ = await vault.adoptExternalChanges(projects: [])

        let selection = await vault.loadGlobalSelection()
        XCTAssertEqual(selection.enabledMCPServerIds, ["on"])
    }

    func testSkillsMoveToVaultFromBothAgentsAndGetEnabled() async throws {
        try makeSkill(named: "from-claude", in: PathConstants.claudeGlobalSkillsDirectory)
        try makeSkill(named: "from-antigravity", in: PathConstants.globalSkillsDirectory)

        let adopted = await vault.adoptExternalChanges(projects: [], minimumSkillAge: 0)

        XCTAssertEqual(adopted.skillIds, ["from-claude", "from-antigravity"])
        XCTAssertTrue(fm.fileExists(atPath: PathConstants.vaultSkillsDirectory.appendingPathComponent("from-claude/SKILL.md").path))
        XCTAssertFalse(fm.fileExists(atPath: PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent("from-claude").path))
    }

    func testSkillStillBeingWrittenAndSyncedFolderStayPut() async throws {
        try makeSkill(named: "fresh", in: PathConstants.claudeGlobalSkillsDirectory)
        try makeSkill(named: "synced", in: PathConstants.claudeGlobalSkillsDirectory)

        let adopted = await vault.adoptExternalChanges(projects: [])

        XCTAssertTrue(adopted.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent("fresh").path))
    }

    func testNoChangesWritesNothing() async throws {
        let adopted = await vault.adoptExternalChanges(projects: [])

        XCTAssertTrue(adopted.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: PathConstants.vaultMCPFile.path))
    }

    func testProjectClaudeSkillIsLinkedForAntigravityAndNotMoved() async throws {
        let projectURL = sandbox.appendingPathComponent("demo", isDirectory: true)
        try makeSkill(named: "local", in: projectURL.appendingPathComponent(".claude/skills", isDirectory: true))
        var hidden = URLResourceValues()
        hidden.isHidden = true
        var hiddenFolder = projectURL.appendingPathComponent(".claude/skills/local", isDirectory: true)
        try hiddenFolder.setResourceValues(hidden)
        let project = ProjectProfile(id: "demo", name: "demo", path: projectURL.path)

        await SyncEngine().linkClaudeProjectSkills(project: project)

        let claudeSkill = projectURL.appendingPathComponent(".claude/skills/local").path
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: claudeSkill), "the committed folder must stay in place")
        let legacyLink = projectURL.appendingPathComponent(".agents/skills/local")
        XCTAssertFalse(fm.fileExists(atPath: legacyLink.path))
        let skillsManifest = projectURL.appendingPathComponent(".agents/skills.json")
        XCTAssertTrue(fm.fileExists(atPath: skillsManifest.path))
        XCTAssertEqual(SyncEngine.readManifestSkillIds(at: projectURL), ["local"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: skillsManifest)) as? [String: Any])
        let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.first?["path"] as? String, ".claude/skills")
        XCTAssertEqual(entries.first?["include_only"] as? [String], ["local"])
    }

    private func makePlugin(named name: String, in directory: URL) throws {
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["name": name]).write(to: folder.appendingPathComponent("plugin.json"))
    }

    func testMarketplacePluginIsCopiedNotMovedAndEnabledGlobally() async throws {
        try makePlugin(named: "chrome-devtools-plugin", in: PathConstants.globalPluginsDirectory)
        try writeJSON([
            "plugins": [
                "chrome-devtools-plugin": [
                    "installedFrom": ["id": "antigravity-plugins-official/plugin/chrome-devtools-plugin"]
                ]
            ]
        ], to: PathConstants.globalAntigravityConfigFile)

        let adopted = await vault.adoptExternalChanges(projects: [], minimumSkillAge: 0)

        XCTAssertEqual(adopted.pluginIds, ["chrome-devtools-plugin"])
        let globalPlugin = PathConstants.globalPluginsDirectory.appendingPathComponent("chrome-devtools-plugin")
        let vaultPlugin = PathConstants.vaultPluginsDirectory.appendingPathComponent("chrome-devtools-plugin")
        XCTAssertTrue(fm.fileExists(atPath: globalPlugin.appendingPathComponent("plugin.json").path), "Marketplace plugin directory must stay in place")
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: globalPlugin.path), "Marketplace plugin must not be replaced by a symlink")
        XCTAssertTrue(fm.fileExists(atPath: vaultPlugin.appendingPathComponent("plugin.json").path), "Marketplace plugin must also be copied into Vault")
        let selection = await vault.loadGlobalSelection()
        XCTAssertTrue(selection.enabledPluginIds.contains("chrome-devtools-plugin"))
    }

    func testLocalGlobalPluginMovesToVaultAndGetsEnabled() async throws {
        try makePlugin(named: "custom-local-plugin", in: PathConstants.globalPluginsDirectory)

        let adopted = await vault.adoptExternalChanges(projects: [], minimumSkillAge: 0)

        XCTAssertEqual(adopted.pluginIds, ["custom-local-plugin"])
        let globalPlugin = PathConstants.globalPluginsDirectory.appendingPathComponent("custom-local-plugin")
        let vaultPlugin = PathConstants.vaultPluginsDirectory.appendingPathComponent("custom-local-plugin")
        XCTAssertFalse(fm.fileExists(atPath: globalPlugin.path))
        XCTAssertTrue(fm.fileExists(atPath: vaultPlugin.appendingPathComponent("plugin.json").path))
        let selection = await vault.loadGlobalSelection()
        XCTAssertTrue(selection.enabledPluginIds.contains("custom-local-plugin"))
    }

    func testSyncGlobalPluginsDoesNotRemoveMarketplacePluginWhenDisabledInSelection() async throws {
        try makePlugin(named: "chrome-devtools-plugin", in: PathConstants.globalPluginsDirectory)
        try writeJSON([
            "plugins": [
                "chrome-devtools-plugin": [
                    "installedFrom": ["id": "antigravity-plugins-official/plugin/chrome-devtools-plugin"]
                ]
            ]
        ], to: PathConstants.globalAntigravityConfigFile)

        let globalPlugin = PathConstants.globalPluginsDirectory.appendingPathComponent("chrome-devtools-plugin")
        let pluginDef = PluginDefinition(
            id: "chrome-devtools-plugin",
            name: "Chrome DevTools",
            description: "Test",
            path: globalPlugin.path,
            hasMCP: false,
            hasSkills: false
        )

        try await SyncEngine().syncGlobalPlugins(allPlugins: [pluginDef], enabledPluginIds: [])

        XCTAssertTrue(fm.fileExists(atPath: globalPlugin.appendingPathComponent("plugin.json").path), "Marketplace plugin must not be moved out of ~/.gemini/config/plugins")
        XCTAssertTrue(fm.fileExists(atPath: PathConstants.vaultPluginsDirectory.appendingPathComponent("chrome-devtools-plugin/plugin.json").path), "Marketplace plugin should be copied to Vault for project reuse")
    }
}
