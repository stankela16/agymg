import Foundation

public enum MCPHealthState: String, Codable, Sendable, Equatable {
    case healthy
    case warning
    case error
    case unknown
}

public struct MCPServerHealthStatus: Codable, Sendable, Equatable, Identifiable {
    public var id: String { serverId }
    public let serverId: String
    public let state: MCPHealthState
    public let summary: String
    public let detail: String
    public let oauthExpiry: Date?
    public let isRemote: Bool

    public init(
        serverId: String,
        state: MCPHealthState,
        summary: String,
        detail: String,
        oauthExpiry: Date? = nil,
        isRemote: Bool
    ) {
        self.serverId = serverId
        self.state = state
        self.summary = summary
        self.detail = detail
        self.oauthExpiry = oauthExpiry
        self.isRemote = isRemote
    }
}

public enum DriftSeverity: String, Codable, Sendable, Equatable {
    case warning
    case error
}

public struct DriftIssue: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let scope: String
    public let target: String
    public let detail: String
    public let severity: DriftSeverity

    public init(id: String, scope: String, target: String, detail: String, severity: DriftSeverity) {
        self.id = id
        self.scope = scope
        self.target = target
        self.detail = detail
        self.severity = severity
    }
}

public struct DriftReport: Codable, Sendable, Equatable {
    public let issues: [DriftIssue]

    public var hasDrift: Bool {
        !issues.isEmpty
    }

    public init(issues: [DriftIssue]) {
        self.issues = issues
    }
}

public struct CLIDoctorAuditSummary: Codable, Sendable, Equatable {
    public let projectId: String
    public let projectName: String
    public let status: String
    public let warnings: [String]

    public init(projectId: String, projectName: String, status: String, warnings: [String]) {
        self.projectId = projectId
        self.projectName = projectName
        self.status = status
        self.warnings = warnings
    }
}

public struct CLIDoctorResponse: Codable, Sendable, Equatable {
    public let status: String
    public let serverHealth: [MCPServerHealthStatus]
    public let driftIssues: [DriftIssue]
    public let projectAudits: [CLIDoctorAuditSummary]
    public let errorCount: Int
    public let warningCount: Int

    public init(
        status: String,
        serverHealth: [MCPServerHealthStatus],
        driftIssues: [DriftIssue],
        projectAudits: [CLIDoctorAuditSummary],
        errorCount: Int,
        warningCount: Int
    ) {
        self.status = status
        self.serverHealth = serverHealth
        self.driftIssues = driftIssues
        self.projectAudits = projectAudits
        self.errorCount = errorCount
        self.warningCount = warningCount
    }
}

public struct MCPDiagnosticsService: Sendable {
    private struct OAuthTokenMeta {
        let hasAccessToken: Bool
        let hasRefreshToken: Bool
        let expiry: Date?
    }

    public init() {}

    public func inspectAllServers(_ servers: [MCPServerDefinition], referenceDate: Date = Date()) -> [String: MCPServerHealthStatus] {
        let oauthMeta = loadOAuthTokenMetadata()
        let needsAuthIds = loadNeedsAuthServerIds()
        var result: [String: MCPServerHealthStatus] = [:]
        for server in servers {
            result[server.id] = inspectServer(
                server,
                oauthMetaByURL: oauthMeta,
                needsAuthServerIds: needsAuthIds,
                referenceDate: referenceDate
            )
        }
        return result
    }

    public func inspectServer(
        _ server: MCPServerDefinition,
        referenceDate: Date = Date()
    ) -> MCPServerHealthStatus {
        inspectServer(
            server,
            oauthMetaByURL: loadOAuthTokenMetadata(),
            needsAuthServerIds: loadNeedsAuthServerIds(),
            referenceDate: referenceDate
        )
    }

    private func inspectServer(
        _ server: MCPServerDefinition,
        oauthMetaByURL: [String: OAuthTokenMeta],
        needsAuthServerIds: Set<String>,
        referenceDate: Date
    ) -> MCPServerHealthStatus {
        if let rawURL = server.serverUrl {
            return inspectRemoteServer(
                server,
                rawURL: rawURL,
                oauthMetaByURL: oauthMetaByURL,
                needsAuthServerIds: needsAuthServerIds,
                referenceDate: referenceDate
            )
        }
        return inspectStdioServer(server)
    }

    private func inspectRemoteServer(
        _ server: MCPServerDefinition,
        rawURL: String,
        oauthMetaByURL: [String: OAuthTokenMeta],
        needsAuthServerIds: Set<String>,
        referenceDate: Date
    ) -> MCPServerHealthStatus {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmedURL),
              let scheme = parsed.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = parsed.host,
              !host.isEmpty else {
            let safeURLDisplay = trimmedURL.components(separatedBy: "?").first ?? trimmedURL
            return MCPServerHealthStatus(
                serverId: server.id,
                state: .error,
                summary: "Invalid URL",
                detail: "Remote server URL '\(safeURLDisplay)' is malformed or missing an HTTP/HTTPS host.",
                isRemote: true
            )
        }

        if let headersObj = server.config["headers"]?.objectValue {
            for (key, value) in headersObj.sorted(by: { $0.key < $1.key }) {
                if let str = value.stringValue, Self.isPlaceholderValue(str) {
                    return MCPServerHealthStatus(
                        serverId: server.id,
                        state: .warning,
                        summary: "Header unconfigured",
                        detail: "HTTP header '\(key)' has an empty or placeholder value.",
                        isRemote: true
                    )
                }
            }
        }

        if needsAuthServerIds.contains(server.id) {
            return MCPServerHealthStatus(
                serverId: server.id,
                state: .warning,
                summary: "Re-auth required",
                detail: "Claude Code authentication cache flagged '\(server.id)' as needing OAuth login.",
                isRemote: true
            )
        }

        let normalizedTarget = SyncEngine.normalizeServerURL(trimmedURL)
        let matchedMeta = oauthMetaByURL[normalizedTarget]
            ?? oauthMetaByURL.first(where: { key, _ in
                normalizedTarget.hasPrefix(key) || key.hasPrefix(normalizedTarget)
            })?.value

        if let meta = matchedMeta {
            if let expiry = meta.expiry {
                if expiry <= referenceDate {
                    if meta.hasRefreshToken {
                        return MCPServerHealthStatus(
                            serverId: server.id,
                            state: .warning,
                            summary: "Token expired (refreshable)",
                            detail: "OAuth access token expired; a refresh token is stored and will renew on next session.",
                            oauthExpiry: expiry,
                            isRemote: true
                        )
                    } else {
                        return MCPServerHealthStatus(
                            serverId: server.id,
                            state: .error,
                            summary: "OAuth expired",
                            detail: "OAuth access token expired with no refresh token stored.",
                            oauthExpiry: expiry,
                            isRemote: true
                        )
                    }
                }
                if expiry.timeIntervalSince(referenceDate) < 86_400 {
                    return MCPServerHealthStatus(
                        serverId: server.id,
                        state: .warning,
                        summary: "OAuth expiring soon",
                        detail: "OAuth token expires within 24 hours.",
                        oauthExpiry: expiry,
                        isRemote: true
                    )
                }
                return MCPServerHealthStatus(
                    serverId: server.id,
                    state: .healthy,
                    summary: "OAuth active",
                    detail: "Valid remote HTTPS/HTTP endpoint (\(host)) with active OAuth session.",
                    oauthExpiry: expiry,
                    isRemote: true
                )
            } else if meta.hasAccessToken || meta.hasRefreshToken {
                return MCPServerHealthStatus(
                    serverId: server.id,
                    state: .healthy,
                    summary: "OAuth configured",
                    detail: "Valid remote endpoint (\(host)) with OAuth credentials present.",
                    isRemote: true
                )
            }
        }

        return MCPServerHealthStatus(
            serverId: server.id,
            state: .healthy,
            summary: "Remote endpoint valid",
            detail: "Remote \(scheme.uppercased()) endpoint configured at \(host).",
            isRemote: true
        )
    }

    private func inspectStdioServer(_ server: MCPServerDefinition) -> MCPServerHealthStatus {
        guard let rawCmd = server.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawCmd.isEmpty else {
            return MCPServerHealthStatus(
                serverId: server.id,
                state: .error,
                summary: "Missing command",
                detail: "MCP server '\(server.id)' has neither a command nor a serverUrl configured.",
                isRemote: false
            )
        }

        guard let resolvedPath = resolveExecutablePath(for: rawCmd) else {
            return MCPServerHealthStatus(
                serverId: server.id,
                state: .error,
                summary: "Binary not found",
                detail: "Executable '\(rawCmd)' was not found on PATH or standard Homebrew/system directories.",
                isRemote: false
            )
        }

        if let envObj = server.config["env"]?.objectValue {
            for (key, value) in envObj.sorted(by: { $0.key < $1.key }) {
                if let str = value.stringValue, Self.isPlaceholderValue(str) {
                    return MCPServerHealthStatus(
                        serverId: server.id,
                        state: .warning,
                        summary: "Env var incomplete",
                        detail: "Environment variable '\(key)' has an empty or placeholder value.",
                        isRemote: false
                    )
                }
            }
        }

        return MCPServerHealthStatus(
            serverId: server.id,
            state: .healthy,
            summary: "Executable ready",
            detail: "Resolved binary at \(resolvedPath).",
            isRemote: false
        )
    }

    public func detectDrift(
        servers: [MCPServerDefinition],
        globalServerIds: Set<String>,
        skills: [SkillDefinition],
        globalSkillIds: Set<String>,
        projects: [ProjectProfile],
        plugins: [PluginDefinition] = [],
        globalPluginIds: Set<String> = []
    ) -> DriftReport {
        let fm = FileManager.default
        var issues: [DriftIssue] = []

        // 1. Global Antigravity mcp_config.json vs Vault global selection
        let agyMCPFile = PathConstants.globalMCPConfigFile.resolvingSymlinksInPath()
        let agyFileExists = fm.fileExists(atPath: agyMCPFile.path)
        if agyFileExists {
            if let data = try? Data(contentsOf: agyMCPFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let mcpServers = json["mcpServers"] as? [String: [String: Any]] {
                for id in globalServerIds.sorted() {
                    guard let entry = mcpServers[id] else {
                        issues.append(DriftIssue(
                            id: "drift:agy-mcp-missing:\(id)",
                            scope: "global",
                            target: "antigravity:mcp_config.json",
                            detail: "Global MCP '\(id)' is missing from ~/.gemini/config/mcp_config.json.",
                            severity: .warning
                        ))
                        continue
                    }
                    if (entry["disabled"] as? Bool) == true {
                        issues.append(DriftIssue(
                            id: "drift:agy-mcp-disabled:\(id)",
                            scope: "global",
                            target: "antigravity:mcp_config.json",
                            detail: "Global MCP '\(id)' is marked disabled in ~/.gemini/config/mcp_config.json.",
                            severity: .warning
                        ))
                    }
                }
                for (id, entry) in mcpServers.sorted(by: { $0.key < $1.key }) {
                    let isEnabledInFile = (entry["disabled"] as? Bool) != true
                    if isEnabledInFile && !globalServerIds.contains(id) {
                        issues.append(DriftIssue(
                            id: "drift:agy-mcp-extra:\(id)",
                            scope: "global",
                            target: "antigravity:mcp_config.json",
                            detail: "MCP '\(id)' is active in ~/.gemini/config/mcp_config.json but not in Global Core.",
                            severity: .warning
                        ))
                    }
                }
            }
        } else if !globalServerIds.isEmpty {
            issues.append(DriftIssue(
                id: "drift:agy-mcp-file-missing",
                scope: "global",
                target: "antigravity:mcp_config.json",
                detail: "~/.gemini/config/mcp_config.json does not exist yet despite \(globalServerIds.count) global MCP(s).",
                severity: .warning
            ))
        }

        // 2. Global Claude ~/.claude.json mcpServers vs globalServerIds
        let claudeFile = PathConstants.claudeConfigFile.resolvingSymlinksInPath()
        let claudeFileExists = fm.fileExists(atPath: claudeFile.path)
        if claudeFileExists {
            if let data = try? Data(contentsOf: claudeFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let claudeServers = (json["mcpServers"] as? [String: Any]) ?? [:]
                for id in globalServerIds.sorted() where claudeServers[id] == nil {
                    issues.append(DriftIssue(
                        id: "drift:claude-mcp-missing:\(id)",
                        scope: "global",
                        target: "claude:.claude.json",
                        detail: "Global MCP '\(id)' is missing from ~/.claude.json mcpServers.",
                        severity: .warning
                    ))
                }
            }
        } else if !globalServerIds.isEmpty {
            issues.append(DriftIssue(
                id: "drift:claude-config-missing",
                scope: "global",
                target: "claude:.claude.json",
                detail: "~/.claude.json does not exist yet despite \(globalServerIds.count) global MCP(s).",
                severity: .warning
            ))
        }

        // 3. Global Skills symlink checks (Antigravity + Claude Code)
        let availableSkillIds = Set(skills.map(\.id))
        let agySkillsDir = PathConstants.globalSkillsDirectory
        let claudeSkillsDir = PathConstants.claudeGlobalSkillsDirectory
        for id in globalSkillIds.sorted() where availableSkillIds.contains(id) {
            let agyLink = agySkillsDir.appendingPathComponent(id)
            if !fm.fileExists(atPath: agyLink.path) {
                let isBrokenSymlink = (try? fm.destinationOfSymbolicLink(atPath: agyLink.path)) != nil
                issues.append(DriftIssue(
                    id: "drift:agy-skill:\(id)",
                    scope: "global",
                    target: "antigravity:skills/\(id)",
                    detail: isBrokenSymlink
                        ? "Broken Antigravity symlink for global skill '\(id)'."
                        : "Global skill '\(id)' is not linked into ~/.gemini/config/skills/.",
                    severity: .warning
                ))
            }

            let claudeLink = claudeSkillsDir.appendingPathComponent(id)
            if !fm.fileExists(atPath: claudeLink.path) {
                let isBrokenSymlink = (try? fm.destinationOfSymbolicLink(atPath: claudeLink.path)) != nil
                issues.append(DriftIssue(
                    id: "drift:claude-skill:\(id)",
                    scope: "global",
                    target: "claude:skills/\(id)",
                    detail: isBrokenSymlink
                        ? "Broken Claude Code symlink for global skill '\(id)'."
                        : "Global skill '\(id)' is not linked into ~/.claude/skills/.",
                    severity: .warning
                ))
            }
        }

        // 4. Project audit drift for scoped projects
        let auditService = ProjectAuditService()
        for project in projects where !project.enabledMCPServerIds.isEmpty || !project.enabledSkillIds.isEmpty || !project.enabledPluginIds.isEmpty {
            let audit = auditService.audit(project: project)
            for item in audit.items {
                if item.status == .failed {
                    issues.append(DriftIssue(
                        id: "drift:proj:\(project.id):\(item.id)",
                        scope: "project:\(project.id)",
                        target: "\(project.name):\(item.title)",
                        detail: item.detail,
                        severity: .error
                    ))
                } else if item.status == .warning {
                    if item.id == "gitignore" && project.enabledMCPServerIds.isEmpty {
                        continue
                    }
                    issues.append(DriftIssue(
                        id: "drift:proj:\(project.id):\(item.id)",
                        scope: "project:\(project.id)",
                        target: "\(project.name):\(item.title)",
                        detail: item.detail,
                        severity: .warning
                    ))
                }
            }
        }

        // 5. Duplicate MCP detection (standalone MCP overlapping an enabled plugin's bundled MCP)
        if !plugins.isEmpty {
            let serverMap = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })

            let globalBundled = PluginScannerService.bundledMCPIndex(for: plugins, enabledPluginIds: globalPluginIds)
            for serverId in globalServerIds.sorted() {
                if let ownerPlugin = globalBundled.conflictingPluginId(for: serverId, server: serverMap[serverId]) {
                    issues.append(DriftIssue(
                        id: "drift:duplicate-mcp:global:\(serverId)",
                        scope: "global",
                        target: "global:\(serverId)",
                        detail: "Standalone MCP '\(serverId)' duplicates MCP bundled in enabled global plugin '\(ownerPlugin)'.",
                        severity: .warning
                    ))
                }
            }

            for project in projects where !project.enabledMCPServerIds.isEmpty && !project.enabledPluginIds.isEmpty {
                let projectBundled = PluginScannerService.bundledMCPIndex(for: plugins, enabledPluginIds: project.enabledPluginIds)
                for serverId in project.enabledMCPServerIds.sorted() {
                    if let ownerPlugin = projectBundled.conflictingPluginId(for: serverId, server: serverMap[serverId]) {
                        issues.append(DriftIssue(
                            id: "drift:duplicate-mcp:proj:\(project.id):\(serverId)",
                            scope: "project:\(project.id)",
                            target: "\(project.name):\(serverId)",
                            detail: "Standalone MCP '\(serverId)' duplicates MCP bundled in enabled plugin '\(ownerPlugin)'.",
                            severity: .warning
                        ))
                    }
                }
            }
        }

        return DriftReport(issues: issues)
    }

    public func runDoctor(
        servers: [MCPServerDefinition],
        globalServerIds: Set<String>,
        skills: [SkillDefinition],
        globalSkillIds: Set<String>,
        projects: [ProjectProfile],
        plugins: [PluginDefinition] = [],
        globalPluginIds: Set<String> = []
    ) -> CLIDoctorResponse {
        let serverMap = inspectAllServers(servers)
        let serverHealth = servers.compactMap { serverMap[$0.id] }.sorted { $0.serverId < $1.serverId }
        let drift = detectDrift(
            servers: servers,
            globalServerIds: globalServerIds,
            skills: skills,
            globalSkillIds: globalSkillIds,
            projects: projects,
            plugins: plugins,
            globalPluginIds: globalPluginIds
        )

        let auditService = ProjectAuditService()
        let projectAudits: [CLIDoctorAuditSummary] = projects.sorted { $0.id < $1.id }.map { project in
            let audit = auditService.audit(project: project)
            let warnings = audit.items.compactMap { item -> String? in
                guard item.status == .warning || item.status == .failed else { return nil }
                if item.id == "gitignore" && project.enabledMCPServerIds.isEmpty && item.status == .warning {
                    return nil
                }
                return "\(item.title): \(item.detail)"
            }
            return CLIDoctorAuditSummary(
                projectId: project.id,
                projectName: project.name,
                status: audit.overallStatus.title,
                warnings: warnings
            )
        }

        let serverErrors = serverHealth.filter { $0.state == .error }.count
        let driftErrors = drift.issues.filter { $0.severity == .error }.count
        let errorCount = serverErrors + driftErrors

        let serverWarnings = serverHealth.filter { $0.state == .warning }.count
        let driftWarnings = drift.issues.filter { $0.severity == .warning }.count
        let warningCount = serverWarnings + driftWarnings

        let status: String
        if errorCount > 0 {
            status = "error"
        } else if warningCount > 0 {
            status = "warning"
        } else {
            status = "healthy"
        }

        return CLIDoctorResponse(
            status: status,
            serverHealth: serverHealth,
            driftIssues: drift.issues,
            projectAudits: projectAudits,
            errorCount: errorCount,
            warningCount: warningCount
        )
    }

    // MARK: - Helpers
    private func resolveExecutablePath(for command: String) -> String? {
        let fm = FileManager.default
        let expanded = (command as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return fm.isExecutableFile(atPath: expanded) ? expanded : nil
        }

        let home = PathConstants.homeDirectory.path
        var searchDirs: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            searchDirs.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }
        searchDirs.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/usr/bin",
            "/bin"
        ])

        var seen: Set<String> = []
        for dir in searchDirs where !dir.isEmpty && seen.insert(dir).inserted {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func loadOAuthTokenMetadata() -> [String: OAuthTokenMeta] {
        var files: [URL] = [PathConstants.engineMCPOAuthTokensFile.resolvingSymlinksInPath()]
        for profHome in PathConstants.antigravityProfileHomes {
            files.append(profHome.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json").resolvingSymlinksInPath())
        }

        var result: [String: OAuthTokenMeta] = [:]
        for fileURL in files {
            guard let data = try? Data(contentsOf: fileURL),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                continue
            }
            for (rawURL, entry) in dict {
                let normalized = SyncEngine.normalizeServerURL(rawURL)
                guard !normalized.isEmpty,
                      let tokenObj = entry["token"] as? [String: Any] else { continue }
                let hasAccess = !((tokenObj["access_token"] as? String) ?? "").isEmpty
                let hasRefresh = !((tokenObj["refresh_token"] as? String) ?? "").isEmpty
                let expiryDate = (tokenObj["expiry"] as? String).flatMap { Self.parseISO8601($0) }

                if let existing = result[normalized] {
                    // Prefer the fresher expiry or stronger credentials across profiles
                    let betterExpiry: Date?
                    switch (existing.expiry, expiryDate) {
                    case (.some(let a), .some(let b)): betterExpiry = max(a, b)
                    case (.none, .some(let b)): betterExpiry = b
                    default: betterExpiry = existing.expiry
                    }
                    result[normalized] = OAuthTokenMeta(
                        hasAccessToken: existing.hasAccessToken || hasAccess,
                        hasRefreshToken: existing.hasRefreshToken || hasRefresh,
                        expiry: betterExpiry
                    )
                } else {
                    result[normalized] = OAuthTokenMeta(
                        hasAccessToken: hasAccess,
                        hasRefreshToken: hasRefresh,
                        expiry: expiryDate
                    )
                }
            }
        }
        return result
    }

    private func loadNeedsAuthServerIds() -> Set<String> {
        var ids: Set<String> = []
        for cacheFile in PathConstants.allClaudeNeedsAuthCacheFiles {
            guard FileManager.default.fileExists(atPath: cacheFile.path),
                  let data = try? Data(contentsOf: cacheFile),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            ids.formUnion(dict.keys)
        }
        return ids
    }

    private static func isPlaceholderValue(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("YOUR_") || upper.contains("REPLACE_ME") || upper.contains("CHANGEME") {
            return true
        }
        if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && trimmed.count > 2 {
            return true
        }
        return false
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: trimmed) { return d }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: trimmed)
    }
}
