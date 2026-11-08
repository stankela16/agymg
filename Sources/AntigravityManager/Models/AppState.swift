import Foundation
import AppKit
import Observation

@MainActor
@Observable
public final class AppState {
    public static let autoFollowUserDefaultsKey = "autoFollowWorkspace"

    public var servers: [MCPServerDefinition] = []
    public var projects: [ProjectProfile] = []
    public var skills: [SkillDefinition] = []
    public var plugins: [PluginDefinition] = []
    public var builtinSkills: [SkillDefinition] = []
    public var slashCommands: [SlashCommandDefinition] = SlashCommandDefinition.standardCommands
    public var projectLocalSkills: [String: [SkillDefinition]] = [:]
    public var projectSafetyAudits: [String: ProjectSafetyAudit] = [:]
    public var projectRecommendations: [String: [ResourceRecommendation]] = [:]
    public var projectStackLabels: [String: [String]] = [:]

    public var globalServerIds: Set<String> = []
    public var globalSkillIds: Set<String> = []
    public var globalPluginIds: Set<String> = []

    public var autoFollowWorkspace: Bool = (UserDefaults.standard.object(forKey: "autoFollowWorkspace") as? Bool) ?? true {
        didSet {
            if !PathConstants.isRunningUnderTests {
                UserDefaults.standard.set(autoFollowWorkspace, forKey: Self.autoFollowUserDefaultsKey)
            }
        }
    }
    public var activeWorkspaceSource: String? = nil

    public var navigationSelection: NavigationSection = .masterVault {
        didSet {
            switch navigationSelection {
            case .project(let id):
                selectedProjectId = id
            case .globalCore:
                selectedProjectId = nil
            default:
                break
            }
        }
    }
    public var selectedProjectId: String?
    public var isSyncing: Bool = false
    public var statusMessage: String?
    public var lastSyncDate: Date? = nil
    public var syncHistory: [SyncLogEntry] = []
    public var isProjectsFolderAuthorized: Bool = ProjectFolderAccessManager.shared.isAuthorized
    public var isAuthorizingFolder: Bool = false

    let vaultService = VaultService()
    let syncEngine = SyncEngine()
    let skillScanner = SkillScannerService()
    let projectScanner = ProjectScannerService()
    let pluginScanner = PluginScannerService()
    let projectAuditService = ProjectAuditService()
    let recommendationService = ProjectRecommendationService()
    @ObservationIgnored let workspaceMonitor = ActiveWorkspaceMonitor()

    @ObservationIgnored private let isAutoloadEnabled: Bool
    @ObservationIgnored var initialLoadTask: Task<Void, Never>?
    @ObservationIgnored var adoptionLoopTask: Task<Void, Never>?
    @ObservationIgnored var syncDebounceTask: Task<Void, Never>?
    @ObservationIgnored var projectSyncDebounceTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var syncAllTask: Task<Void, Never>?
    @ObservationIgnored var lastLocalChangeDate = Date.distantPast

    public init(autoload: Bool = true) {
        self.isAutoloadEnabled = autoload
        if autoload {
            workspaceMonitor.start(with: self)
            initialLoadTask = Task { [weak self] in
                await self?.loadData()
                guard !Task.isCancelled, !PathConstants.isRunningUnderTests else { return }
                await self?.workspaceMonitor.checkIDefocusWorkspace()
                self?.startAdoptionLoopIfNeeded()
            }
        }
    }

    func startAdoptionLoopIfNeeded() {
        guard isAutoloadEnabled, !PathConstants.isRunningUnderTests, adoptionLoopTask == nil else { return }
        adoptionLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.adoptExternalChanges()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    public var selectedProject: ProjectProfile? {
        guard let id = selectedProjectId else { return nil }
        return projects.first { $0.id == id }
    }

    public var activeProjectRecommendations: [ResourceRecommendation] {
        guard let selectedProject else { return [] }
        return projectRecommendations[selectedProject.id] ?? []
    }

    public var hasActiveProjectRecommendations: Bool {
        !activeProjectRecommendations.isEmpty
    }

    public func recommendations(for project: ProjectProfile) -> [ResourceRecommendation] {
        projectRecommendations[project.id] ?? []
    }

    public func logSyncEvent(
        status: SyncLogStatus,
        category: SyncLogCategory = .system,
        targetName: String,
        message: String,
        details: String? = nil,
        duration: TimeInterval? = nil
    ) {
        let entry = SyncLogEntry(
            status: status,
            category: category,
            targetName: targetName,
            message: message,
            details: details,
            duration: duration
        )
        syncHistory.insert(entry, at: 0)
        if syncHistory.count > 500 {
            syncHistory.removeLast(syncHistory.count - 500)
        }
    }

    public func clearSyncHistory() {
        syncHistory.removeAll()
    }

    public func cancelPendingTasks() {
        initialLoadTask?.cancel()
        initialLoadTask = nil
        adoptionLoopTask?.cancel()
        adoptionLoopTask = nil
        syncDebounceTask?.cancel()
        syncDebounceTask = nil
        for (_, task) in projectSyncDebounceTasks {
            task.cancel()
        }
        projectSyncDebounceTasks.removeAll()
        syncAllTask?.cancel()
        syncAllTask = nil
    }

    public func flushPendingSync() async {
        if let task = syncDebounceTask {
            task.cancel()
            syncDebounceTask = nil
            await performGlobalSync()
        }
        let pendingProjectIds = Array(projectSyncDebounceTasks.keys)
        for projectId in pendingProjectIds {
            projectSyncDebounceTasks[projectId]?.cancel()
            projectSyncDebounceTasks.removeValue(forKey: projectId)
            await performProjectSync(projectId: projectId)
        }
    }

    public func loadData() async {
        guard !Task.isCancelled else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }

        await vaultService.initializeVaultIfNeeded()
        guard !Task.isCancelled else { return }

        let (loadedServers, newGlobalIds) = await vaultService.scanAndIngestServers()
        let globalSelection = await vaultService.loadGlobalSelection()
        guard !Task.isCancelled else { return }

        let sScanner = self.skillScanner
        let (scannedSkills, scannedBuiltins) = await Task.detached(priority: .userInitiated) {
            let s = sScanner.scanVaultSkills()
            let b = sScanner.scanBuiltinSkills()
            return (s, b)
        }.value
        guard !Task.isCancelled else { return }

        self.servers = loadedServers
        self.skills = scannedSkills
        self.builtinSkills = scannedBuiltins

        self.globalServerIds = globalSelection.enabledMCPServerIds.union(newGlobalIds)
        self.globalSkillIds = globalSelection.enabledSkillIds
        self.globalPluginIds = globalSelection.enabledPluginIds

        if isProjectsFolderAuthorized {
            guard !Task.isCancelled else { return }
            let loadedProjects = await vaultService.loadProjects()
            guard !Task.isCancelled else { return }
            let pScanner = self.pluginScanner
            let sScanner = self.skillScanner
            let aService = self.projectAuditService
            let (scannedPlugins, scannedLocalSkills, scannedAudits) = await Task.detached(priority: .userInitiated) {
                let p = pScanner.scanAllPlugins(projects: loadedProjects)
                let ls = sScanner.scanAllProjectLocalSkills(projects: loadedProjects)
                var audits: [String: ProjectSafetyAudit] = [:]
                for proj in loadedProjects {
                    audits[proj.id] = aService.audit(project: proj)
                }
                return (p, ls, audits)
            }.value
            guard !Task.isCancelled else { return }
            self.projects = loadedProjects
            self.plugins = scannedPlugins
            self.projectLocalSkills = scannedLocalSkills
            self.projectSafetyAudits = scannedAudits

            let (updatedServers, _) = await vaultService.scanAndIngestServers(projects: loadedProjects)
            self.servers = updatedServers
            await refreshAllRecommendations()

            if autoFollowWorkspace, let ctx = await vaultService.loadActiveContext() {
                _ = applyDetectedWorkspace(path: ctx.projectPath, source: ctx.source, updateNavigationIfNotProject: false)
            }

            if selectedProjectId == nil, let first = projects.first {
                selectedProjectId = first.id
            }
        } else {
            let pScanner = self.pluginScanner
            let scannedPlugins = await Task.detached(priority: .userInitiated) {
                pScanner.scanAllPlugins(projects: [])
            }.value
            self.projects = []
            self.plugins = scannedPlugins
            self.projectLocalSkills = [:]
            self.projectSafetyAudits = [:]
            self.projectRecommendations = [:]
            self.projectStackLabels = [:]
        }

        self.logSyncEvent(
            status: .info,
            category: .system,
            targetName: "System Engine",
            message: "System initialized with \(self.servers.count) MCPs, \(self.skills.count) skills, \(self.plugins.count) plugins, \(self.projects.count) projects",
            details: "Master Vault catalog initialized and local environments scanned."
        )
    }

    @discardableResult
    public func authorizeProjectsFolder(
        customURL: URL? = nil,
        updateAuthorizationState: Bool = true
    ) async -> Bool {
        isAuthorizingFolder = true
        defer { isAuthorizingFolder = false }

        let result = await ProjectFolderAccessManager.shared.requestAuthorization(customURL: customURL)
        if result.success, let url = result.url {
            await applyAuthorizedDirectory(url: url, updateAuthorizationState: updateAuthorizationState)
            return true
        }
        return false
    }

    public func applyAuthorizedDirectory(url: URL, updateAuthorizationState: Bool = true) async {
        initialLoadTask?.cancel()
        initialLoadTask = nil
        await vaultService.initializeVaultIfNeeded()

        let scanner = self.projectScanner
        let pScanner = self.pluginScanner
        let sScanner = self.skillScanner
        let aService = self.projectAuditService
        let needSkillScan = self.skills.isEmpty
        let (discovered, scannedPlugins, scannedLocalSkills, scannedAudits, vaultSkills, builtinSk) = await Task.detached(priority: .userInitiated) {
            let disc = scanner.discoverProjects(in: url)
            let plugins = pScanner.scanAllPlugins(projects: disc)
            let localSkills = sScanner.scanAllProjectLocalSkills(projects: disc)
            var audits: [String: ProjectSafetyAudit] = [:]
            for proj in disc {
                audits[proj.id] = aService.audit(project: proj)
            }
            let vs = needSkillScan ? sScanner.scanVaultSkills() : []
            let bs = needSkillScan ? sScanner.scanBuiltinSkills() : []
            return (disc, plugins, localSkills, audits, vs, bs)
        }.value

        if needSkillScan {
            let globalSelection = await vaultService.loadGlobalSelection()
            self.skills = vaultSkills
            self.builtinSkills = builtinSk
            if self.globalServerIds.isEmpty {
                self.globalServerIds = globalSelection.enabledMCPServerIds
            }
            if self.globalSkillIds.isEmpty {
                self.globalSkillIds = globalSelection.enabledSkillIds
            }
            if self.globalPluginIds.isEmpty {
                self.globalPluginIds = globalSelection.enabledPluginIds
            }
        }

        self.projects = discovered
        self.plugins = scannedPlugins
        self.projectLocalSkills = scannedLocalSkills
        self.projectSafetyAudits = scannedAudits
        await vaultService.saveProjects(discovered)

        let (ingestedServers, newGlobalIds) = await vaultService.scanAndIngestServers(projects: discovered)
        self.servers = ingestedServers
        if !newGlobalIds.isEmpty {
            self.globalServerIds.formUnion(newGlobalIds)
        }

        await refreshAllRecommendations()

        if let first = discovered.first {
            selectedProjectId = first.id
        }
        if updateAuthorizationState {
            isProjectsFolderAuthorized = true
        }
        startAdoptionLoopIfNeeded()
        statusMessage = "Connected to \(url.lastPathComponent): \(discovered.count) projects found"
    }

    public func resetProjectsFolderAuthorization() {
        ProjectFolderAccessManager.shared.resetAuthorization()
        isProjectsFolderAuthorized = false
        projects = []
        plugins = []
        projectLocalSkills = [:]
        projectSafetyAudits = [:]
        projectRecommendations = [:]
        projectStackLabels = [:]
        navigationSelection = .masterVault
        statusMessage = "Projects folder authorization reset"
    }

    public func reloadSkills() {
        let scanner = self.skillScanner
        let aService = self.projectAuditService
        let curProjects = self.projects
        Task { [weak self] in
            let (s, b, localSkillsDict, auditsDict) = await Task.detached(priority: .userInitiated) {
                let s = scanner.scanVaultSkills()
                let b = scanner.scanBuiltinSkills()
                let ls = scanner.scanAllProjectLocalSkills(projects: curProjects)
                var audits: [String: ProjectSafetyAudit] = [:]
                for p in curProjects {
                    audits[p.id] = aService.audit(project: p)
                }
                return (s, b, ls, audits)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.skills = s
            self.builtinSkills = b
            self.projectLocalSkills = localSkillsDict
            self.projectSafetyAudits = auditsDict
            await self.refreshAllRecommendations()
        }
    }

    public func localSkills(for project: ProjectProfile) -> [SkillDefinition] {
        if let cached = projectLocalSkills[project.id] {
            return cached
        }
        return skillScanner.scanProjectLocalSkills(projectPath: project.path)
    }

    public func safetyAudit(for project: ProjectProfile) -> ProjectSafetyAudit {
        projectSafetyAudits[project.id] ?? ProjectSafetyAudit.checking(for: project)
    }

    public func refreshSafetyAudit(for project: ProjectProfile) async {
        let service = self.projectAuditService
        let audit = await Task.detached(priority: .utility) {
            service.audit(project: project)
        }.value
        self.projectSafetyAudits[project.id] = audit
    }

    public func refreshAllSafetyAudits() async {
        let service = self.projectAuditService
        let curProjects = self.projects
        let audits = await Task.detached(priority: .utility) {
            var map: [String: ProjectSafetyAudit] = [:]
            for p in curProjects {
                map[p.id] = service.audit(project: p)
            }
            return map
        }.value
        self.projectSafetyAudits = audits
    }

    public func refreshAllRecommendations() async {
        let recService = self.recommendationService
        let curProjects = self.projects
        let curServers = self.servers
        let curGlobalS = self.globalServerIds
        let curSkills = self.skills
        let curGlobalSk = self.globalSkillIds
        let curLocalSk = self.projectLocalSkills
        let curPlugins = self.plugins
        let curGlobalP = self.globalPluginIds

        let (computedRecs, computedStacks) = await Task.detached(priority: .utility) {
            var map: [String: [ResourceRecommendation]] = [:]
            var stacks: [String: [String]] = [:]
            for proj in curProjects {
                let localIds = Set((curLocalSk[proj.id] ?? []).map(\.id))
                let stack = recService.inspectStack(at: proj.path)
                stacks[proj.id] = stack.stackLabels
                map[proj.id] = recService.buildRecommendations(
                    stack: stack,
                    project: proj,
                    availableServers: curServers,
                    globalServerIds: curGlobalS,
                    availableSkills: curSkills,
                    globalSkillIds: curGlobalSk,
                    projectLocalSkillIds: localIds,
                    availablePlugins: curPlugins,
                    globalPluginIds: curGlobalP
                )
            }
            return (map, stacks)
        }.value
        self.projectRecommendations = computedRecs
        self.projectStackLabels = computedStacks
    }

    public func refreshRecommendations(for projectId: String) async {
        guard let proj = projects.first(where: { $0.id == projectId }) else { return }
        let recService = self.recommendationService
        let curServers = self.servers
        let curGlobalS = self.globalServerIds
        let curSkills = self.skills
        let curGlobalSk = self.globalSkillIds
        let localIds = Set((self.projectLocalSkills[proj.id] ?? []).map(\.id))
        let curPlugins = self.plugins
        let curGlobalP = self.globalPluginIds

        let (recs, labels) = await Task.detached(priority: .utility) {
            let stack = recService.inspectStack(at: proj.path)
            let built = recService.buildRecommendations(
                stack: stack,
                project: proj,
                availableServers: curServers,
                globalServerIds: curGlobalS,
                availableSkills: curSkills,
                globalSkillIds: curGlobalSk,
                projectLocalSkillIds: localIds,
                availablePlugins: curPlugins,
                globalPluginIds: curGlobalP
            )
            return (built, stack.stackLabels)
        }.value
        self.projectRecommendations[proj.id] = recs
        self.projectStackLabels[proj.id] = labels
    }

    public func enableRecommendedResource(_ rec: ResourceRecommendation, for projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        switch rec.kind {
        case .mcp:
            projects[index].enabledMCPServerIds.insert(rec.id)
        case .skill:
            projects[index].enabledSkillIds.insert(rec.id)
        case .plugin:
            projects[index].enabledPluginIds.insert(rec.id)
        }
        projectRecommendations[projectId]?.removeAll { $0.uniqueKey == rec.uniqueKey }
        triggerProjectSync(project: projects[index], debounceNanoseconds: 150_000_000)
    }

    public func enableAllRecommendations(for projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }),
              let recs = projectRecommendations[projectId], !recs.isEmpty else { return }
        for rec in recs {
            switch rec.kind {
            case .mcp:
                projects[index].enabledMCPServerIds.insert(rec.id)
            case .skill:
                projects[index].enabledSkillIds.insert(rec.id)
            case .plugin:
                projects[index].enabledPluginIds.insert(rec.id)
            }
        }
        projectRecommendations[projectId] = []
        triggerProjectSync(project: projects[index], debounceNanoseconds: 150_000_000)
    }

    @discardableResult
    public func applyDetectedWorkspace(
        path: String,
        source: String = "auto",
        forceEvenIfAutoFollowOff: Bool = false,
        updateNavigationIfNotProject: Bool = true
    ) -> ProjectProfile? {
        guard autoFollowWorkspace || forceEvenIfAutoFollowOff else { return nil }
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let sortedByDepth = projects.sorted {
            URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path.count >
            URL(fileURLWithPath: $1.path).resolvingSymlinksInPath().path.count
        }
        guard let matched = sortedByDepth.first(where: { proj in
            let projCanonical = URL(fileURLWithPath: proj.path).resolvingSymlinksInPath().path
            return canonical == projCanonical || canonical.hasPrefix(projCanonical + "/")
        }) else {
            return nil
        }

        selectedProjectId = matched.id
        activeWorkspaceSource = source
        if updateNavigationIfNotProject {
            if case .project = navigationSelection {
                navigationSelection = .project(matched.id)
            }
        }
        return matched
    }

    public func reloadFromVaultAfterCLI(preferredProjectPath: String? = nil, source: String = "cli") async {
        lastLocalChangeDate = Date()
        syncDebounceTask?.cancel()
        syncDebounceTask = nil
        for (_, task) in projectSyncDebounceTasks {
            task.cancel()
        }
        projectSyncDebounceTasks.removeAll()
        await loadData()
        if let preferredProjectPath, !preferredProjectPath.isEmpty {
            _ = applyDetectedWorkspace(path: preferredProjectPath, source: source)
        }
    }

    public func registerProjectFolder(at url: URL) async {
        let canonicalURL = url.resolvingSymlinksInPath()
        let path = canonicalURL.path
        let name = canonicalURL.lastPathComponent

        guard FileManager.default.fileExists(atPath: path) else {
            statusMessage = "Project folder does not exist at the specified path"
            return
        }

        if let existing = projects.first(where: { $0.path == path }) {
            selectedProjectId = existing.id
            navigationSelection = .project(existing.id)
            statusMessage = "Project '\(existing.name)' is already registered"
            return
        }

        let pScanner = self.pluginScanner
        let sScanner = self.skillScanner
        let aService = self.projectAuditService
        let existingIds = Set(projects.map(\.id))
        let uniqueId = existingIds.contains(name)
            ? "\(name)_\(PathConstants.stableShortHash(path, length: 6))"
            : name
        let (newProject, scannedLocalSkills, auditForProject) = await Task.detached(priority: .userInitiated) { () -> (ProjectProfile, [SkillDefinition], ProjectSafetyAudit) in
            var proj = ProjectProfile(id: uniqueId, name: name, path: path)
            let fm = FileManager.default

            // Scan local plugins and MCP servers in the newly imported project
            let pluginsDir = canonicalURL.appendingPathComponent(".agents/plugins", isDirectory: true)
            if let pluginFolders = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
                for pluginFolder in pluginFolders where !pluginFolder.lastPathComponent.hasPrefix(".") {
                    let pluginName = pluginFolder.lastPathComponent
                    guard PathConstants.isSafeResourceId(pluginName) else { continue }
                    if pluginName != "agy-manager" {
                        proj.enabledPluginIds.insert(pluginName)
                    }
                    let mcpFile = pluginFolder.appendingPathComponent("mcp_config.json")
                    if let data = try? Data(contentsOf: mcpFile),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let servers = json["mcpServers"] as? [String: Any] {
                        for serverKey in servers.keys where PathConstants.isSafeResourceId(serverKey) {
                            proj.enabledMCPServerIds.insert(serverKey)
                        }
                    }
                }
            }

            // Scan local skills in the newly imported project
            let skillsDir = canonicalURL.appendingPathComponent(".agents/skills", isDirectory: true)
            if let skillFolders = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) {
                for skillFolder in skillFolders where !skillFolder.lastPathComponent.hasPrefix(".") {
                    let skillName = skillFolder.lastPathComponent
                    guard PathConstants.isSafeResourceId(skillName) else { continue }
                    proj.enabledSkillIds.insert(skillName)
                }
            }

            let localSkills = sScanner.scanProjectLocalSkills(projectPath: path)
            let audit = aService.audit(project: proj)
            return (proj, localSkills, audit)
        }.value

        projects.append(newProject)
        projects.sort { $0.name.lowercased() < $1.name.lowercased() }
        projectLocalSkills[newProject.id] = scannedLocalSkills
        projectSafetyAudits[newProject.id] = auditForProject
        await vaultService.saveProjects(projects)

        let allProjects = self.projects
        let rescannedPlugins = await Task.detached(priority: .userInitiated) {
            pScanner.scanAllPlugins(projects: allProjects)
        }.value
        self.plugins = rescannedPlugins

        let (rescannedServers, _) = await vaultService.scanAndIngestServers(projects: allProjects)
        self.servers = rescannedServers
        await refreshRecommendations(for: newProject.id)

        isProjectsFolderAuthorized = true
        selectedProjectId = newProject.id
        navigationSelection = .project(newProject.id)
        statusMessage = "Imported project '\(name)'"
    }

    public func newProjectDialog() {
        WindowRouter.dismissPopover()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "New Antigravity Project"
        panel.prompt = "Create"
        panel.message = "Choose a location and name for your new Antigravity workspace"
        panel.nameFieldStringValue = "new-project"
        panel.canCreateDirectories = true
        panel.directoryURL = ProjectFolderAccessManager.shared.targetDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                Task {
                    await registerProjectFolder(at: url)
                }
            } catch {
                statusMessage = "Error creating project: \(error.localizedDescription)"
            }
        }
    }

    public func openProjectDialog() {
        WindowRouter.dismissPopover()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Import Project"
        panel.prompt = "Import Project"
        panel.message = "Select a project folder to register in Antigravity Manager"
        panel.directoryURL = ProjectFolderAccessManager.shared.targetDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await registerProjectFolder(at: url)
            }
        }
    }

    // MARK: - External Application Launching
    public func openTerminal(for projectPath: String) {
        let trimmed = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDir: ObjCBool = false
        guard !trimmed.isEmpty,
              FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir),
              isDir.boolValue else {
            statusMessage = "Project folder does not exist at the specified path"
            return
        }

        let projectURL = URL(fileURLWithPath: trimmed)
        let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

        // Never launch external Terminal.app or trigger LaunchServices UI during unit tests
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            statusMessage = "Terminal ready for: \(projectURL.lastPathComponent)"
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.promptsUserIfNeeded = false
        NSWorkspace.shared.open([projectURL], withApplicationAt: terminalURL, configuration: config) { _, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Error opening Terminal: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Vault Skill Creation
    @discardableResult
    public func createVaultSkill(
        id: String,
        name: String,
        description: String,
        category: String? = nil,
        initialContent: String? = nil
    ) async throws -> SkillDefinition {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !cleanId.isEmpty else {
            throw NSError(domain: "SkillCreation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Skill ID cannot be empty"])
        }
        guard PathConstants.isSafeResourceId(cleanId) else {
            throw NSError(domain: "SkillCreation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Skill ID cannot contain path separators or traversal segments"])
        }

        let folderURL = PathConstants.vaultSkillsDirectory.appendingPathComponent(cleanId, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folderURL.path) {
            throw NSError(domain: "SkillCreation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Skill with ID '\(cleanId)' already exists in Master Vault"])
        }

        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanId : name
        let skillCategory = category ?? SkillDefinition.guessCategory(for: cleanId)

        let markdown: String
        if let initialContent, !initialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            markdown = initialContent
        } else {
            markdown = """
            ---
            name: \(displayName)
            description: \(description)
            ---

            # \(displayName)

            \(description)

            ## Overview
            Instructions and guidelines for this skill.
            """
        }

        let skillFile = folderURL.appendingPathComponent("SKILL.md")
        try markdown.write(to: skillFile, atomically: true, encoding: .utf8)

        let newSkill = SkillDefinition(
            id: cleanId,
            name: displayName,
            description: description,
            category: skillCategory,
            path: folderURL.path,
            origin: .vault
        )

        // Instant reactivity in memory
        skills.removeAll { $0.id == cleanId }
        skills.append(newSkill)
        skills.sort { $0.name.lowercased() < $1.name.lowercased() }

        reloadSkills()

        logSyncEvent(
            status: .success,
            category: .vault,
            targetName: displayName,
            message: "Created new skill '\(cleanId)' in Master Vault"
        )
        statusMessage = "Created skill '\(displayName)'"
        return newSkill
    }

    // MARK: - MCP Server Management
    public func saveServer(_ server: MCPServerDefinition, enableGlobally: Bool = false) async {
        guard PathConstants.isSafeResourceId(server.id) else {
            statusMessage = "Invalid MCP server ID"
            return
        }
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
            servers.sort { $0.name.lowercased() < $1.name.lowercased() }
        }

        if enableGlobally {
            globalServerIds.insert(server.id)
        }

        await vaultService.saveServers(servers)
        triggerSync(debounceNanoseconds: 0)

        logSyncEvent(
            status: .success,
            category: .vault,
            targetName: server.name,
            message: "Saved MCP server '\(server.id)' to Master Vault"
        )
        statusMessage = "Saved MCP server '\(server.name)'"
    }

    // MARK: - Configuration Backups
    @discardableResult
    public func createManualConfigBackup() async -> URL? {
        if let snapshotURL = await syncEngine.createConfigSnapshotIfNeeded(force: true) {
            logSyncEvent(
                status: .success,
                category: .system,
                targetName: "Config Backup",
                message: "Created configuration snapshot '\(snapshotURL.lastPathComponent)'",
                details: snapshotURL.path
            )
            statusMessage = "Backup created: \(snapshotURL.lastPathComponent)"
            return snapshotURL
        } else {
            statusMessage = "Failed to create configuration backup"
            return nil
        }
    }
}
