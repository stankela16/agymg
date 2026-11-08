import Foundation

extension AppState {
    // MARK: - Global Toggles
    // MARK: - Global Toggles
    public func toggleGlobalServer(id: String) {
        if globalServerIds.contains(id) {
            globalServerIds.remove(id)
        } else {
            globalServerIds.insert(id)
        }
        triggerSync(debounceNanoseconds: 250_000_000)
    }

    public func toggleGlobalSkill(id: String) {
        if globalSkillIds.contains(id) {
            globalSkillIds.remove(id)
        } else {
            globalSkillIds.insert(id)
        }
        triggerSync(debounceNanoseconds: 250_000_000)
    }

    public func toggleGlobalPlugin(id: String) {
        if globalPluginIds.contains(id) {
            globalPluginIds.remove(id)
        } else {
            globalPluginIds.insert(id)
        }
        triggerSync(debounceNanoseconds: 250_000_000)
    }

    // MARK: - Project Toggles
    public func toggleProjectServer(projectId: String, serverId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        if projects[index].enabledMCPServerIds.contains(serverId) {
            projects[index].enabledMCPServerIds.remove(serverId)
        } else {
            projects[index].enabledMCPServerIds.insert(serverId)
        }
        triggerProjectSync(project: projects[index], debounceNanoseconds: 250_000_000)
    }

    public func toggleProjectSkill(projectId: String, skillId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        if projects[index].enabledSkillIds.contains(skillId) {
            projects[index].enabledSkillIds.remove(skillId)
        } else {
            projects[index].enabledSkillIds.insert(skillId)
        }
        triggerProjectSync(project: projects[index], debounceNanoseconds: 250_000_000)
    }

    public func toggleProjectPlugin(projectId: String, pluginId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        if projects[index].enabledPluginIds.contains(pluginId) {
            projects[index].enabledPluginIds.remove(pluginId)
        } else {
            projects[index].enabledPluginIds.insert(pluginId)
        }
        triggerProjectSync(project: projects[index], debounceNanoseconds: 250_000_000)
    }

    func triggerSync(debounceNanoseconds: UInt64 = 0) {
        lastLocalChangeDate = Date()
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            await self.performGlobalSync()
        }
    }

    func performGlobalSync() async {
        guard !Task.isCancelled else { return }
        let startTime = CFAbsoluteTimeGetCurrent()
        let curServers = self.servers
        let curGlobalS = self.globalServerIds
        let curSkills = self.skills
        let curGlobalSk = self.globalSkillIds
        let curPlugins = self.plugins
        let curGlobalP = self.globalPluginIds

        do {
            await self.vaultService.saveGlobalSelection(GlobalSelection(
                enabledMCPServerIds: curGlobalS,
                enabledSkillIds: curGlobalSk,
                enabledPluginIds: curGlobalP
            ))
            guard !Task.isCancelled else { return }
            try await self.syncEngine.syncGlobalConfig(servers: curServers, enabledIds: curGlobalS)
            guard !Task.isCancelled else { return }
            try await self.syncEngine.syncGlobalSkills(allSkills: curSkills, enabledSkillIds: curGlobalSk)
            guard !Task.isCancelled else { return }
            try await self.syncEngine.syncGlobalPlugins(allPlugins: curPlugins, enabledPluginIds: curGlobalP)

            guard !Task.isCancelled else { return }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            self.lastSyncDate = Date()
            self.statusMessage = "Global profile synchronized"
            self.logSyncEvent(
                status: .success,
                category: .global,
                targetName: "Global Core",
                message: "Global core synchronized (\(curGlobalS.count) MCPs, \(curGlobalSk.count) skills, \(curGlobalP.count) plugins)",
                details: "Updated ~/.gemini/config/mcp_config.json\nLinked \(curGlobalSk.count) skills and \(curGlobalP.count) plugins",
                duration: duration
            )
            await self.refreshAllRecommendations()
        } catch {
            guard !Task.isCancelled else { return }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            self.statusMessage = "Global profile sync error: \(error.localizedDescription)"
            self.logSyncEvent(
                status: .failure,
                category: .global,
                targetName: "Global Core",
                message: "Failed to synchronize Global Core",
                details: error.localizedDescription,
                duration: duration
            )
        }
    }

    func triggerProjectSync(project: ProjectProfile, debounceNanoseconds: UInt64 = 0) {
        lastLocalChangeDate = Date()
        let projectId = project.id
        projectSyncDebounceTasks[projectId]?.cancel()
        projectSyncDebounceTasks[projectId] = Task { [weak self] in
            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            await self.performProjectSync(projectId: projectId)
        }
    }

    func performProjectSync(projectId: String) async {
        guard !Task.isCancelled else { return }
        guard let currentProject = self.projects.first(where: { $0.id == projectId }) else { return }
        let startTime = CFAbsoluteTimeGetCurrent()
        let curProjects = self.projects
        let curServers = self.servers
        let curSkills = self.skills
        let curPlugins = self.plugins

        do {
            await self.vaultService.saveProjects(curProjects)
            guard !Task.isCancelled else { return }
            try await self.syncEngine.syncProject(
                project: currentProject,
                allServers: curServers,
                allSkills: curSkills,
                allPlugins: curPlugins
            )
            guard !Task.isCancelled else { return }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            self.lastSyncDate = Date()
            self.statusMessage = "Synchronized project: \(currentProject.name)"
            self.logSyncEvent(
                status: .success,
                category: .project,
                targetName: currentProject.name,
                message: "Synchronized '\(currentProject.name)' (\(currentProject.enabledMCPServerIds.count) MCPs, \(currentProject.enabledSkillIds.count) skills, \(currentProject.enabledPluginIds.count) plugins)",
                details: "Generated .agents/plugins/agy-manager at \(currentProject.path)",
                duration: duration
            )
            await self.refreshSafetyAudit(for: currentProject)
            await self.refreshRecommendations(for: currentProject.id)
        } catch {
            guard !Task.isCancelled else { return }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            self.statusMessage = "Error synchronizing project \(currentProject.name): \(error.localizedDescription)"
            self.logSyncEvent(
                status: .failure,
                category: .project,
                targetName: currentProject.name,
                message: "Failed to synchronize project '\(currentProject.name)'",
                details: error.localizedDescription,
                duration: duration
            )
        }
    }

    public func syncProject(_ project: ProjectProfile) {
        triggerProjectSync(project: project)
    }

    public func syncAll() {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = "Synchronizing all components..."

        let curServers = servers
        let curGlobalS = globalServerIds
        let curSkills = skills
        let curGlobalSk = globalSkillIds
        let curPlugins = plugins
        let curGlobalP = globalPluginIds
        let curProjects = projects

        syncAllTask?.cancel()
        syncAllTask = Task { [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()
            defer { self?.isSyncing = false }
            do {
                guard let self, !Task.isCancelled else { return }
                try await self.syncEngine.syncAll(
                    servers: curServers,
                    globalServerIds: curGlobalS,
                    skills: curSkills,
                    globalSkillIds: curGlobalSk,
                    plugins: curPlugins,
                    globalPluginIds: curGlobalP,
                    projects: curProjects
                )
                guard !Task.isCancelled else { return }
                await self.vaultService.saveGlobalSelection(GlobalSelection(
                    enabledMCPServerIds: curGlobalS,
                    enabledSkillIds: curGlobalSk,
                    enabledPluginIds: curGlobalP
                ))
                guard !Task.isCancelled else { return }
                await self.vaultService.saveProjects(curProjects)
                guard !Task.isCancelled else { return }
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                self.lastSyncDate = Date()
                self.statusMessage = "All components synchronized to disk!"
                self.logSyncEvent(
                    status: .success,
                    category: .all,
                    targetName: "All Workspaces",
                    message: "Full synchronization complete across \(curProjects.count) projects and Global Core",
                    details: "Global: \(curGlobalS.count) MCPs, \(curGlobalSk.count) skills, \(curGlobalP.count) plugins\nProjects: \(curProjects.map(\.name).joined(separator: ", "))",
                    duration: duration
                )
            } catch {
                guard let self, !Task.isCancelled else { return }
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                self.statusMessage = "Synchronization failed: \(error.localizedDescription)"
                self.logSyncEvent(
                    status: .failure,
                    category: .all,
                    targetName: "All Workspaces",
                    message: "Full synchronization failed",
                    details: error.localizedDescription,
                    duration: duration
                )
            }
        }
    }

    /// Picks up what was added in Claude Code or Antigravity and spreads it to the other one.
    func adoptExternalChanges() async {
        // A toggle made here a moment ago is not on disk yet and must not read as an external change.
        guard !isSyncing, Date().timeIntervalSince(lastLocalChangeDate) > 3 else { return }

        let curProjects = projects
        for project in curProjects {
            await syncEngine.linkClaudeProjectSkills(project: project)
        }

        let adopted = await vaultService.adoptExternalChanges(
            projects: curProjects,
            ignoredServerIds: pluginBundledServerIds()
        )
        guard !adopted.isEmpty else { return }

        await loadData()
        if !adopted.serverIds.isEmpty || !adopted.skillIds.isEmpty {
            await performGlobalSync()
        }
        for projectId in adopted.projectIds {
            await performProjectSync(projectId: projectId)
        }
        logSyncEvent(
            status: .info,
            category: .system,
            targetName: "External Changes",
            message: "Adopted \(adopted.serverIds.count) MCPs and \(adopted.skillIds.count) skills from Claude Code / Antigravity",
            details: (adopted.serverIds.sorted() + adopted.skillIds.sorted()).joined(separator: ", ")
        )
    }

    /// Servers inside plugins are written to Claude by the plugin sync and do not belong in the Vault catalog.
    private func pluginBundledServerIds() -> Set<String> {
        var ids: Set<String> = []
        for plugin in plugins where plugin.hasMCP && plugin.id != "agy-manager" {
            let file = URL(fileURLWithPath: plugin.path).appendingPathComponent("mcp_config.json")
            if let data = try? Data(contentsOf: file),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servers = json["mcpServers"] as? [String: Any] {
                ids.formUnion(servers.keys)
            }
        }
        return ids
    }

    public func refreshProjects() async {
        guard isProjectsFolderAuthorized else {
            let sScanner = self.skillScanner
            let (rescannedSkills, rescannedBuiltins) = await Task.detached(priority: .userInitiated) {
                let sk = sScanner.scanVaultSkills()
                let bk = sScanner.scanBuiltinSkills()
                return (sk, bk)
            }.value
            let (rescannedServers, newGlobalServerIds) = await vaultService.scanAndIngestServers(projects: [])
            self.servers = rescannedServers
            if !newGlobalServerIds.isEmpty {
                self.globalServerIds.formUnion(newGlobalServerIds)
            }
            self.skills = rescannedSkills
            self.builtinSkills = rescannedBuiltins
            statusMessage = "Refreshed: \(self.servers.count) MCP servers, \(rescannedSkills.count) skills"
            return
        }
        let targetDir = ProjectFolderAccessManager.shared.authorizedDirectoryURL
        let scanner = self.projectScanner
        let sScanner = self.skillScanner
        let pScanner = self.pluginScanner
        let existingProjects = self.projects

        let (discovered, rescannedSkills, rescannedBuiltins) = await Task.detached(priority: .userInitiated) {
            let disc = scanner.discoverProjects(in: targetDir, scanDefaultWhenNil: false)
            let sk = sScanner.scanVaultSkills()
            let bk = sScanner.scanBuiltinSkills()
            return (disc, sk, bk)
        }.value

        var updated: [ProjectProfile] = []
        for disc in discovered {
            if let existing = existingProjects.first(where: { $0.path == disc.path }) {
                var merged = disc
                merged.enabledMCPServerIds.formUnion(existing.enabledMCPServerIds)
                merged.enabledSkillIds.formUnion(existing.enabledSkillIds)
                merged.enabledPluginIds.formUnion(existing.enabledPluginIds)
                updated.append(merged)
            } else {
                updated.append(disc)
            }
        }
        // Preserve custom imported projects whose directories still exist
        for existing in existingProjects {
            if !updated.contains(where: { $0.path == existing.path }) && FileManager.default.fileExists(atPath: existing.path) {
                updated.append(existing)
            }
        }
        updated.sort { $0.name.lowercased() < $1.name.lowercased() }

        let projectsForScanning = updated
        let aService = self.projectAuditService
        let (rescannedPlugins, rescannedLocalSkills, rescannedAudits) = await Task.detached(priority: .userInitiated) {
            let plugins = pScanner.scanAllPlugins(projects: projectsForScanning)
            let localSkills = sScanner.scanAllProjectLocalSkills(projects: projectsForScanning)
            var audits: [String: ProjectSafetyAudit] = [:]
            for p in projectsForScanning {
                audits[p.id] = aService.audit(project: p)
            }
            return (plugins, localSkills, audits)
        }.value

        let (rescannedServers, newGlobalServerIds) = await vaultService.scanAndIngestServers(projects: updated)

        self.projects = updated
        await vaultService.saveProjects(updated)

        self.servers = rescannedServers
        if !newGlobalServerIds.isEmpty {
            self.globalServerIds.formUnion(newGlobalServerIds)
        }

        self.skills = rescannedSkills
        self.plugins = rescannedPlugins
        self.builtinSkills = rescannedBuiltins
        self.projectLocalSkills = rescannedLocalSkills
        self.projectSafetyAudits = rescannedAudits
        await refreshAllRecommendations()

        if selectedProjectId == nil || !updated.contains(where: { $0.id == selectedProjectId }) {
            selectedProjectId = updated.first?.id
        }

        statusMessage = "Refreshed: \(self.servers.count) MCP servers, \(rescannedSkills.count) skills, \(updated.count) projects"
    }
}
