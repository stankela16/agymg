import Foundation

extension SyncEngine {
    // MARK: - Permanent Deletion / Uninstall
    public func purgeServerCompletely(id: String, allProjects: [ProjectProfile]) throws {
        let globalFile = PathConstants.globalMCPConfigFile
        let canonicalGlobalFile = globalFile.resolvingSymlinksInPath()
        if let data = try? Data(contentsOf: canonicalGlobalFile),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var servers = json["mcpServers"] as? [String: Any] {
            servers.removeValue(forKey: id)
            json["mcpServers"] = servers
            let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: canonicalGlobalFile, options: .atomic)
        }

        let fm = FileManager.default
        for project in allProjects {
            let mcpFile = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins/agy-manager/mcp_config.json")
            if let data = try? Data(contentsOf: mcpFile),
               var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               var servers = json["mcpServers"] as? [String: Any] {
                servers.removeValue(forKey: id)
                if servers.isEmpty {
                    let pluginDir = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins/agy-manager")
                    try? fm.removeItem(at: pluginDir)
                } else {
                    json["mcpServers"] = servers
                    let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
                    try updatedData.write(to: mcpFile, options: .atomic)
                }
            }
        }

        let localShareDir = PathConstants.effectiveHomeDirectory.appendingPathComponent(".local/share/\(id)-mcp")
        if fm.fileExists(atPath: localShareDir.path) {
            try? fm.removeItem(at: localShareDir)
        }

        // Purge from Claude ~/.claude.json across primary home and all AntigravityProfiles
        for configFile in PathConstants.allClaudeConfigFiles {
            let claudeConfigURL = configFile.resolvingSymlinksInPath()
            if let data = try? Data(contentsOf: claudeConfigURL),
               var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if var globalServers = json["mcpServers"] as? [String: Any] {
                    globalServers.removeValue(forKey: id)
                    json["mcpServers"] = globalServers
                }
                if var projectsDict = json["projects"] as? [String: Any] {
                    for project in allProjects {
                        if var projEntry = projectsDict[project.path] as? [String: Any],
                           var projServers = projEntry["mcpServers"] as? [String: Any] {
                            projServers.removeValue(forKey: id)
                            projEntry["mcpServers"] = projServers
                            projectsDict[project.path] = projEntry
                        }
                    }
                    json["projects"] = projectsDict
                }
                if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                    try? updatedData.write(to: claudeConfigURL, options: .atomic)
                }
            }
        }
    }

    public func purgeSkillCompletely(id: String, allProjects: [ProjectProfile]) {
        let fm = FileManager.default
        let globalSkillURL = PathConstants.globalSkillsDirectory.appendingPathComponent(id)
        if fm.fileExists(atPath: globalSkillURL.path) || (try? fm.destinationOfSymbolicLink(atPath: globalSkillURL.path)) != nil {
            try? fm.removeItem(at: globalSkillURL)
        }

        let claudeGlobalSkillURL = PathConstants.claudeGlobalSkillsDirectory.appendingPathComponent(id)
        if fm.fileExists(atPath: claudeGlobalSkillURL.path) || (try? fm.destinationOfSymbolicLink(atPath: claudeGlobalSkillURL.path)) != nil {
            try? fm.removeItem(at: claudeGlobalSkillURL)
        }

        for project in allProjects {
            let projectSkillURL = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/skills/\(id)")
            if fm.fileExists(atPath: projectSkillURL.path) || (try? fm.destinationOfSymbolicLink(atPath: projectSkillURL.path)) != nil {
                try? fm.removeItem(at: projectSkillURL)
            }
            let claudeProjectSkillURL = URL(fileURLWithPath: project.path).appendingPathComponent(".claude/skills/\(id)")
            if (try? fm.destinationOfSymbolicLink(atPath: claudeProjectSkillURL.path)) != nil {
                try? fm.removeItem(at: claudeProjectSkillURL)
            }
        }
    }

    public func purgePluginCompletely(id: String, allProjects: [ProjectProfile]) {
        let fm = FileManager.default
        let globalPluginURL = PathConstants.globalPluginsDirectory.appendingPathComponent(id)
        if fm.fileExists(atPath: globalPluginURL.path) || (try? fm.destinationOfSymbolicLink(atPath: globalPluginURL.path)) != nil {
            try? fm.removeItem(at: globalPluginURL)
        }

        for project in allProjects {
            let projectPluginURL = URL(fileURLWithPath: project.path).appendingPathComponent(".agents/plugins/\(id)")
            if fm.fileExists(atPath: projectPluginURL.path) || (try? fm.destinationOfSymbolicLink(atPath: projectPluginURL.path)) != nil {
                try? fm.removeItem(at: projectPluginURL)
            }
        }
    }
}
