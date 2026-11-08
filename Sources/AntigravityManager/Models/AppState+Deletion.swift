import Foundation

extension AppState {
    // MARK: - Permanent Deletion
    public func deleteServer(id: String) async {
        servers.removeAll { $0.id == id }
        globalServerIds.remove(id)
        for i in 0..<projects.count {
            projects[i].enabledMCPServerIds.remove(id)
        }

        try? await syncEngine.purgeServerCompletely(id: id, allProjects: projects)
        await vaultService.deleteServer(id: id)
        await vaultService.saveGlobalSelection(GlobalSelection(
            enabledMCPServerIds: globalServerIds,
            enabledSkillIds: globalSkillIds,
            enabledPluginIds: globalPluginIds
        ))
        await vaultService.saveProjects(projects)
        statusMessage = "Uninstalled MCP server \(id)"
    }

    public func deleteSkill(id: String) async {
        skills.removeAll { $0.id == id }
        globalSkillIds.remove(id)
        for i in 0..<projects.count {
            projects[i].enabledSkillIds.remove(id)
        }

        await syncEngine.purgeSkillCompletely(id: id, allProjects: projects)
        await vaultService.deleteSkill(id: id)
        await vaultService.saveGlobalSelection(GlobalSelection(
            enabledMCPServerIds: globalServerIds,
            enabledSkillIds: globalSkillIds,
            enabledPluginIds: globalPluginIds
        ))
        await vaultService.saveProjects(projects)
        statusMessage = "Uninstalled skill \(id)"
    }

    public func deletePlugin(id: String) async {
        plugins.removeAll { $0.id == id }
        globalPluginIds.remove(id)
        for i in 0..<projects.count {
            projects[i].enabledPluginIds.remove(id)
        }

        await syncEngine.purgePluginCompletely(id: id, allProjects: projects)
        await vaultService.deletePlugin(id: id)
        await vaultService.saveGlobalSelection(GlobalSelection(
            enabledMCPServerIds: globalServerIds,
            enabledSkillIds: globalSkillIds,
            enabledPluginIds: globalPluginIds
        ))
        await vaultService.saveProjects(projects)
        statusMessage = "Uninstalled plugin \(id)"
    }

    public func removeProject(id: String) async {
        projects.removeAll { $0.id == id }
        await vaultService.saveProjects(projects)
        if selectedProjectId == id {
            selectedProjectId = projects.first?.id
            if let first = projects.first {
                navigationSelection = .project(first.id)
            } else {
                navigationSelection = .masterVault
            }
        }
        statusMessage = "Removed project from manager"
    }
}
