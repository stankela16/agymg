import Foundation

public struct ProjectAuditService: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    public init(fileManager: FileManager) {
        self.init()
    }

    public func audit(project: ProjectProfile) -> ProjectSafetyAudit {
        let pathItem = auditPath(project: project)
        guard pathItem.status != .failed else {
            return ProjectSafetyAudit(
                pathCheck: pathItem,
                gitignoreCheck: ProjectSafetyAudit.AuditItem(
                    id: "gitignore",
                    title: ".gitignore Protection",
                    detail: "Project directory unavailable",
                    status: .failed
                ),
                manifestCheck: ProjectSafetyAudit.AuditItem(
                    id: "manifest",
                    title: "Runtime Manifest",
                    detail: "Project directory unavailable",
                    status: .failed
                ),
                symlinkCheck: ProjectSafetyAudit.AuditItem(
                    id: "symlinks",
                    title: "Asset Symlinks",
                    detail: "Project directory unavailable",
                    status: .failed
                )
            )
        }

        let gitignoreItem = auditGitignore(project: project)
        let manifestItem = auditManifest(project: project)
        let symlinkItem = auditSymlinks(project: project)

        return ProjectSafetyAudit(
            pathCheck: pathItem,
            gitignoreCheck: gitignoreItem,
            manifestCheck: manifestItem,
            symlinkCheck: symlinkItem
        )
    }

    public func auditPath(project: ProjectProfile) -> ProjectSafetyAudit.AuditItem {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: project.path, isDirectory: &isDir)
        guard exists else {
            return ProjectSafetyAudit.AuditItem(
                id: "path",
                title: "Project Directory",
                detail: "Path does not exist on disk: \(project.path)",
                status: .failed
            )
        }
        guard isDir.boolValue else {
            return ProjectSafetyAudit.AuditItem(
                id: "path",
                title: "Project Directory",
                detail: "Path is not a directory",
                status: .failed
            )
        }
        return ProjectSafetyAudit.AuditItem(
            id: "path",
            title: "Project Directory",
            detail: "Path verified on disk",
            status: .passed
        )
    }

    public func auditGitignore(project: ProjectProfile) -> ProjectSafetyAudit.AuditItem {
        let projectURL = URL(fileURLWithPath: project.path)
        let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
        let gitDirURL = projectURL.appendingPathComponent(".git")
        let hasGit = fileManager.fileExists(atPath: gitDirURL.path)

        guard fileManager.fileExists(atPath: gitignoreURL.path) else {
            if hasGit {
                return ProjectSafetyAudit.AuditItem(
                    id: "gitignore",
                    title: ".gitignore Protection",
                    detail: "Git repository has no .gitignore (secrets are not protected)",
                    status: .warning
                )
            } else {
                return ProjectSafetyAudit.AuditItem(
                    id: "gitignore",
                    title: ".gitignore Protection",
                    detail: "No .gitignore file found (recommended before committing)",
                    status: .warning
                )
            }
        }

        guard let content = try? String(contentsOf: gitignoreURL, encoding: .utf8) else {
            return ProjectSafetyAudit.AuditItem(
                id: "gitignore",
                title: ".gitignore Protection",
                detail: "Failed to read .gitignore file",
                status: .warning
            )
        }

        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let isProtected = lines.contains { rawLine in
            let line = rawLine.hasPrefix("/") ? String(rawLine.dropFirst()) : rawLine
            return line == ".agents" || line == ".agents/" || line == ".agents/*"
                || line == ".agents/plugins" || line == ".agents/plugins/" || line == ".agents/plugins/*"
                || line == ".agents/plugins/agy-manager" || line == ".agents/plugins/agy-manager/" || line == ".agents/plugins/agy-manager/*"
        }

        if isProtected {
            return ProjectSafetyAudit.AuditItem(
                id: "gitignore",
                title: ".gitignore Protection",
                detail: ".gitignore protects .agents/plugins/agy-manager and MCP tokens",
                status: .passed
            )
        } else {
            return ProjectSafetyAudit.AuditItem(
                id: "gitignore",
                title: ".gitignore Protection",
                detail: "Missing rule for .agents/plugins/agy-manager (secret leak risk)",
                status: .warning
            )
        }
    }

    public func auditManifest(project: ProjectProfile) -> ProjectSafetyAudit.AuditItem {
        let projectURL = URL(fileURLWithPath: project.path)
        let pluginDir = projectURL.appendingPathComponent(".agents/plugins/agy-manager", isDirectory: true)
        let manifestURL = pluginDir.appendingPathComponent("mcp_config.json")

        if project.enabledMCPServerIds.isEmpty {
            if fileManager.fileExists(atPath: manifestURL.path) {
                if let data = try? Data(contentsOf: manifestURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let servers = json["mcpServers"] as? [String: Any],
                   !servers.isEmpty {
                    return ProjectSafetyAudit.AuditItem(
                        id: "manifest",
                        title: "Runtime Manifest",
                        detail: "Stale manifest contains \(servers.count) servers while profile is empty",
                        status: .warning
                    )
                }
            }
            return ProjectSafetyAudit.AuditItem(
                id: "manifest",
                title: "Runtime Manifest",
                detail: "Synchronized (0 project servers)",
                status: .passed
            )
        }

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ProjectSafetyAudit.AuditItem(
                id: "manifest",
                title: "Runtime Manifest",
                detail: "mcp_config.json does not exist on disk (sync required)",
                status: .warning
            )
        }

        guard let data = try? Data(contentsOf: manifestURL) else {
            return ProjectSafetyAudit.AuditItem(
                id: "manifest",
                title: "Runtime Manifest",
                detail: "Failed to read mcp_config.json",
                status: .failed
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            return ProjectSafetyAudit.AuditItem(
                id: "manifest",
                title: "Runtime Manifest",
                detail: "mcp_config.json contains invalid JSON",
                status: .failed
            )
        }

        let diskServerKeys = Set(servers.keys)
        if diskServerKeys == project.enabledMCPServerIds {
            return ProjectSafetyAudit.AuditItem(
                id: "manifest",
                title: "Runtime Manifest",
                detail: "Synchronized (\(diskServerKeys.count) servers valid)",
                status: .passed
            )
        } else {
            let missing = project.enabledMCPServerIds.subtracting(diskServerKeys)
            let extra = diskServerKeys.subtracting(project.enabledMCPServerIds)
            var diff: [String] = []
            if !missing.isEmpty { diff.append("missing: \(missing.joined(separator: ", "))") }
            if !extra.isEmpty { diff.append("extra: \(extra.joined(separator: ", "))") }
            return ProjectSafetyAudit.AuditItem(
                id: "manifest",
                title: "Runtime Manifest",
                detail: "Out of sync (\(diff.joined(separator: "; ")))",
                status: .warning
            )
        }
    }

    public func auditSymlinks(project: ProjectProfile) -> ProjectSafetyAudit.AuditItem {
        let projectURL = URL(fileURLWithPath: project.path)
        let skillsDir = projectURL.appendingPathComponent(".agents/skills", isDirectory: true)

        var brokenLinks: [String] = []
        if fileManager.fileExists(atPath: skillsDir.path) {
            if let files = try? fileManager.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) {
                for file in files {
                    if (try? fileManager.destinationOfSymbolicLink(atPath: file.path)) != nil {
                        if !fileManager.fileExists(atPath: file.path) {
                            brokenLinks.append(file.lastPathComponent)
                        }
                    }
                }
            }
        }

        if !brokenLinks.isEmpty {
            return ProjectSafetyAudit.AuditItem(
                id: "symlinks",
                title: "Asset Symlinks",
                detail: "Broken symlinks found: \(brokenLinks.joined(separator: ", "))",
                status: .warning
            )
        }

        return ProjectSafetyAudit.AuditItem(
            id: "symlinks",
            title: "Asset Symlinks",
            detail: "All symlinks valid and isolated",
            status: .passed
        )
    }
}
