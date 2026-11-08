import Foundation

public struct ProjectScannerService: Sendable {
    public init() {}

    public func discoverProjects(in customDirectory: URL? = nil, scanDefaultWhenNil: Bool = true) -> [ProjectProfile] {
        let fm = FileManager.default
        var projectsByPath: [String: ProjectProfile] = [:]
        var canonicalSeen: Set<String> = []
        var usedIds: Set<String> = []

        let targetProjectsDir: URL? = customDirectory ?? (scanDefaultWhenNil ? PathConstants.defaultProjectsDirectory : nil)
        let authorizedPrefix = targetProjectsDir?.resolvingSymlinksInPath().path

        func registerCandidate(name: String, path: String) {
            let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard !canonicalSeen.contains(canonical), projectsByPath[path] == nil else { return }
            let uniqueId: String
            if usedIds.contains(name) {
                let parentName = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
                let candidate = parentName.isEmpty ? "\(name)-\(abs(canonical.hashValue % 10000))" : "\(parentName)-\(name)"
                uniqueId = usedIds.contains(candidate) ? "\(name)-\(abs(canonical.hashValue % 10000))" : candidate
            } else {
                uniqueId = name
            }
            canonicalSeen.insert(canonical)
            usedIds.insert(uniqueId)
            projectsByPath[path] = ProjectProfile(id: uniqueId, name: name, path: path)
        }

        // 1. Scan registered projects in ~/.gemini/config/projects/
        let configProjectsDir = PathConstants.globalProjectsDirectory
        if let files = try? fm.contentsOfDirectory(at: configProjectsDir, includingPropertiesForKeys: nil) {
            for fileURL in files where fileURL.pathExtension == "json" {
                if let (name, path) = parseProjectConfig(fileURL: fileURL) {
                    if canProbePathWithoutTCCPrompt(path, authorizedPrefix: authorizedPrefix),
                       fm.fileExists(atPath: path) {
                        registerCandidate(name: name, path: path)
                    }
                }
            }
        }

        // 2. Scan Projects directory (custom or default Projects directory)
        if let targetProjectsDir,
           let subdirs = try? fm.contentsOfDirectory(at: targetProjectsDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for dir in subdirs {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                    let folderName = dir.lastPathComponent
                    if !folderName.hasPrefix("."), folderName != "archived" {
                        registerCandidate(name: folderName, path: dir.path)
                    }
                }
            }
        }

        // 3. Scan existing valid project paths from ~/.claude.json ("projects" map)
        let claudeConfig = PathConstants.claudeConfigFile
        var claudeProjectsMap: [String: [String: Any]] = [:]
        if let data = try? Data(contentsOf: claudeConfig),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let claudeProjects = root["projects"] as? [String: [String: Any]] {
            claudeProjectsMap = claudeProjects
            for rawPath in claudeProjects.keys.sorted() {
                guard isValidClaudeProjectCandidate(rawPath, authorizedPrefix: authorizedPrefix, fileManager: fm) else {
                    continue
                }
                let folderName = URL(fileURLWithPath: rawPath).lastPathComponent
                guard !folderName.isEmpty, folderName != "archived" else { continue }
                registerCandidate(name: folderName, path: rawPath)
            }
        }

        // 4. Inspect each project for existing .agents/plugins/, .agents/skills/, and Claude project MCPs
        var discovered = Array(projectsByPath.values)
        for i in 0..<discovered.count {
            let projectPath = discovered[i].path
            let pluginsDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".agents/plugins", isDirectory: true)
            if let pluginFolders = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
                for pluginFolder in pluginFolders where !pluginFolder.lastPathComponent.hasPrefix(".") {
                    let pluginName = pluginFolder.lastPathComponent
                    if pluginName != "agy-manager" {
                        discovered[i].enabledPluginIds.insert(pluginName)
                    }
                    let mcpFile = pluginFolder.appendingPathComponent("mcp_config.json")
                    if let data = try? Data(contentsOf: mcpFile),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let servers = json["mcpServers"] as? [String: Any] {
                        for serverKey in servers.keys {
                            discovered[i].enabledMCPServerIds.insert(serverKey)
                        }
                    }
                }
            }

            let directMcpFile = URL(fileURLWithPath: projectPath).appendingPathComponent(".agents/mcp_config.json")
            if let data = try? Data(contentsOf: directMcpFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servers = json["mcpServers"] as? [String: Any] {
                for serverKey in servers.keys {
                    discovered[i].enabledMCPServerIds.insert(serverKey)
                }
            }

            if let claudeEntry = claudeProjectsMap[projectPath],
               let claudeServers = claudeEntry["mcpServers"] as? [String: Any] {
                for serverKey in claudeServers.keys {
                    discovered[i].enabledMCPServerIds.insert(serverKey)
                }
            }

            let skillsDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".agents/skills", isDirectory: true)
            if let skillFolders = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) {
                for skillFolder in skillFolders where !skillFolder.lastPathComponent.hasPrefix(".") {
                    let skillName = skillFolder.lastPathComponent
                    discovered[i].enabledSkillIds.insert(skillName)
                }
            }
        }

        return discovered.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func canProbePathWithoutTCCPrompt(_ path: String, authorizedPrefix: String?) -> Bool {
        if PathConstants.isRunningUnderTests || PathConstants.customGeminiDirectory != nil || PathConstants.hasEnvironmentOverride {
            return true
        }
        let home = PathConstants.homeDirectory.resolvingSymlinksInPath().path
        let protectedPrefixes = [
            home + "/Desktop",
            home + "/Documents",
            home + "/Downloads"
        ]
        let isProtected = protectedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
        guard isProtected else { return true }
        guard let authorizedPrefix else { return false }
        return path == authorizedPrefix || path.hasPrefix(authorizedPrefix + "/")
    }

    private func isValidClaudeProjectCandidate(
        _ rawPath: String,
        authorizedPrefix: String?,
        fileManager fm: FileManager
    ) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        guard canProbePathWithoutTCCPrompt(trimmed, authorizedPrefix: authorizedPrefix) else { return false }

        let canonical = URL(fileURLWithPath: trimmed).resolvingSymlinksInPath().path
        let home = PathConstants.homeDirectory.resolvingSymlinksInPath().path
        let effectiveHome = PathConstants.effectiveHomeDirectory.resolvingSymlinksInPath().path
        let geminiDir = PathConstants.geminiDirectory.resolvingSymlinksInPath().path
        let claudeDir = PathConstants.claudeDirectory.resolvingSymlinksInPath().path

        let exactExcluded: Set<String> = ["/", "/tmp", "/private/tmp", "/var", "/private/var", home, effectiveHome]
        if exactExcluded.contains(canonical) || exactExcluded.contains(trimmed) {
            return false
        }
        if canonical.hasPrefix(geminiDir + "/") || canonical.hasPrefix(claudeDir + "/") || canonical == geminiDir || canonical == claudeDir {
            return false
        }
        if !PathConstants.isRunningUnderTests && PathConstants.customGeminiDirectory == nil && !PathConstants.hasEnvironmentOverride {
            if canonical.hasPrefix("/tmp/") || canonical.hasPrefix("/private/tmp/") {
                return false
            }
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: canonical, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let markers = [".git", ".claude", ".agents", "Package.swift", "package.json", "pyproject.toml", "Cargo.toml", "go.mod"]
        let dirURL = URL(fileURLWithPath: canonical, isDirectory: true)
        return markers.contains { fm.fileExists(atPath: dirURL.appendingPathComponent($0).path) }
    }

    private func parseProjectConfig(fileURL: URL) -> (name: String, path: String)? {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            return nil
        }

        var projectPath: String?
        if let resourcesDict = json["projectResources"] as? [String: Any],
           let resources = resourcesDict["resources"] as? [[String: Any]] {
            for res in resources {
                if let gitFolder = res["gitFolder"] as? [String: Any],
                   let folderUri = gitFolder["folderUri"] as? String,
                   let url = URL(string: folderUri) {
                    projectPath = url.path
                    break
                }
            }
        }

        // Fallback: Check if <defaultProjectsDirectory>/<name> exists
        if projectPath == nil || projectPath?.isEmpty == true {
            let fallback = PathConstants.defaultProjectsDirectory.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: fallback) {
                projectPath = fallback
            }
        }

        guard let path = projectPath, !path.isEmpty else { return nil }
        return (name, path)
    }
}
