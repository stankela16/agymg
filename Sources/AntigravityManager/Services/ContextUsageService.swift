import Foundation

/// Read-only background actor that computes Context Footprint (skill frontmatter / full sizes,
/// MCP tool schema sizes) and 30-day Observation Window usage counts from local Antigravity
/// and Claude Code transcripts with incremental mtime+size caching.
public actor ContextUsageService {
    public struct Configuration: Sendable {
        public let claudeProjectsRoot: URL?
        public let antigravityBrainRoots: [URL]
        public let antigravityMCPSchemaRoots: [URL]
        public let observationWindowDays: Int

        public init(
            claudeProjectsRoot: URL?,
            antigravityBrainRoots: [URL],
            antigravityMCPSchemaRoots: [URL],
            observationWindowDays: Int = 30
        ) {
            self.claudeProjectsRoot = claudeProjectsRoot
            self.antigravityBrainRoots = antigravityBrainRoots
            self.antigravityMCPSchemaRoots = antigravityMCPSchemaRoots
            self.observationWindowDays = observationWindowDays
        }

        public static func liveDefault() -> Configuration {
            if PathConstants.isRunningUnderTests {
                return Configuration(
                    claudeProjectsRoot: nil,
                    antigravityBrainRoots: [],
                    antigravityMCPSchemaRoots: [],
                    observationWindowDays: 30
                )
            }

            let home = PathConstants.homeDirectory
            let fm = FileManager.default

            var brainRoots: [URL] = []
            var schemaRoots: [URL] = []

            let defaultAgy = home.appendingPathComponent(".gemini/antigravity", isDirectory: true)
            let defaultBrain = defaultAgy.appendingPathComponent("brain", isDirectory: true)
            let defaultMCP = defaultAgy.appendingPathComponent("mcp", isDirectory: true)
            if fm.fileExists(atPath: defaultBrain.path) { brainRoots.append(defaultBrain) }
            if fm.fileExists(atPath: defaultMCP.path) { schemaRoots.append(defaultMCP) }

            let profilesRoot = home.appendingPathComponent("AntigravityProfiles", isDirectory: true)
            if let profileDirs = try? fm.contentsOfDirectory(
                at: profilesRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for dir in profileDirs {
                    let agy = dir.appendingPathComponent("home/.gemini/antigravity", isDirectory: true)
                    let brain = agy.appendingPathComponent("brain", isDirectory: true)
                    let mcp = agy.appendingPathComponent("mcp", isDirectory: true)
                    if fm.fileExists(atPath: brain.path) { brainRoots.append(brain) }
                    if fm.fileExists(atPath: mcp.path) { schemaRoots.append(mcp) }
                }
            }

            let claudeProjects = home.appendingPathComponent(".claude/projects", isDirectory: true)
            return Configuration(
                claudeProjectsRoot: fm.fileExists(atPath: claudeProjects.path) ? claudeProjects : nil,
                antigravityBrainRoots: brainRoots,
                antigravityMCPSchemaRoots: schemaRoots,
                observationWindowDays: 30
            )
        }
    }

    private struct CachedTranscriptEntry {
        let modificationDate: Date
        let fileSize: Int64
        let mcpCounts: [String: Int]
        let skillCounts: [String: Int]
        let matchedProjectIds: [String]
    }

    private let configuration: Configuration
    private var transcriptCache: [String: CachedTranscriptEntry] = [:]
    private var cachedProjectsFingerprint: String = ""

    public init(configuration: Configuration = .liveDefault()) {
        self.configuration = configuration
    }

    public func computeSnapshot(
        servers: [MCPServerDefinition],
        skills: [SkillDefinition],
        projects: [ProjectProfile],
        now: Date = Date()
    ) -> ContextUsageSnapshot {
        let skillFootprints = computeSkillFootprints(skills: skills)
        let mcpFootprints = computeMCPFootprints(servers: servers)

        let projectsFingerprint = projects
            .map { "\($0.id)=\($0.path.lowercased())" }
            .sorted()
            .joined(separator: "|")
        if projectsFingerprint != cachedProjectsFingerprint {
            transcriptCache.removeAll()
            cachedProjectsFingerprint = projectsFingerprint
        }

        let cutoffDate = now.addingTimeInterval(-TimeInterval(configuration.observationWindowDays) * 86_400)
        let usage = scanTranscripts(projects: projects, cutoffDate: cutoffDate)

        return ContextUsageSnapshot(
            mcpFootprints: mcpFootprints,
            skillFootprints: skillFootprints,
            mcpUsage: usage.mcpUsage,
            skillUsage: usage.skillUsage,
            scannedSessionsCount: usage.sessionCount,
            lastUpdated: now
        )
    }

    // MARK: - Context Footprint

    private func computeSkillFootprints(skills: [SkillDefinition]) -> [String: ResourceFootprint] {
        var result: [String: ResourceFootprint] = [:]
        for skill in skills {
            let skillFile = URL(fileURLWithPath: skill.path).appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else {
                let fallbackChars = skill.name.count + skill.description.count + 40
                let tok = max(1, fallbackChars / 4)
                result[skill.id] = ResourceFootprint(
                    antigravityStartupTokens: tok,
                    claudeStartupTokens: tok,
                    onDemandTokens: tok
                )
                continue
            }

            let frontmatterChars = extractFrontmatterLength(from: content)
            let startupChars = frontmatterChars + skillFile.path.count + 20
            let startupTokens = max(1, startupChars / 4)
            let fullTokens = max(startupTokens, content.utf8.count / 4)

            result[skill.id] = ResourceFootprint(
                antigravityStartupTokens: startupTokens,
                claudeStartupTokens: startupTokens,
                onDemandTokens: fullTokens
            )
        }
        return result
    }

    private func extractFrontmatterLength(from content: String) -> Int {
        guard content.hasPrefix("---") else {
            return min(content.count, 320)
        }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 2 else { return min(content.count, 320) }
        var total = 0
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                return total
            }
            total += line.utf8.count + 1
        }
        return min(content.count, 320)
    }

    private func computeMCPFootprints(servers: [MCPServerDefinition]) -> [String: ResourceFootprint] {
        let fm = FileManager.default
        var result: [String: ResourceFootprint] = [:]

        for server in servers {
            var bestToolCount = 0
            var bestSchemaBytes = 0

            for root in configuration.antigravityMCPSchemaRoots {
                let serverDir = root.appendingPathComponent(server.id, isDirectory: true)
                guard let files = try? fm.contentsOfDirectory(
                    at: serverDir,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                let jsonFiles = files.filter { $0.pathExtension.lowercased() == "json" }
                if jsonFiles.count > bestToolCount {
                    bestToolCount = jsonFiles.count
                    bestSchemaBytes = jsonFiles.reduce(0) { acc, file in
                        let sz = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        return acc + sz
                    }
                }
            }

            if bestToolCount > 0 {
                // Antigravity lazy-loads tool names (~6 tokens/tool); Claude Code eagerly loads full JSON schemas.
                let agyStartup = max(12, bestToolCount * 6 + 10)
                let ccStartup = max(agyStartup, bestSchemaBytes / 4)
                result[server.id] = ResourceFootprint(
                    antigravityStartupTokens: agyStartup,
                    claudeStartupTokens: ccStartup,
                    onDemandTokens: ccStartup,
                    toolCount: bestToolCount
                )
            } else {
                // Conservative fallback when no cached tool schemas exist on disk yet.
                result[server.id] = ResourceFootprint(
                    antigravityStartupTokens: 45,
                    claudeStartupTokens: 1_500,
                    onDemandTokens: 1_500,
                    toolCount: 0
                )
            }
        }
        return result
    }

    // MARK: - Local Transcript Usage Scanning

    private struct UsageAggregation {
        let mcpUsage: [String: ResourceUsageStats]
        let skillUsage: [String: ResourceUsageStats]
        let sessionCount: Int
    }

    private func scanTranscripts(projects: [ProjectProfile], cutoffDate: Date) -> UsageAggregation {
        let fm = FileManager.default
        var mcpTotals: [String: Int] = [:]
        var mcpByProject: [String: [String: Int]] = [:]
        var mcpLastUsed: [String: Date] = [:]

        var skillTotals: [String: Int] = [:]
        var skillByProject: [String: [String: Int]] = [:]
        var skillLastUsed: [String: Date] = [:]

        var sessionCount = 0
        var seenFilePaths = Set<String>()

        func merge(entry: CachedTranscriptEntry) {
            for (serverId, count) in entry.mcpCounts {
                mcpTotals[serverId, default: 0] += count
                if let existing = mcpLastUsed[serverId] {
                    if entry.modificationDate > existing { mcpLastUsed[serverId] = entry.modificationDate }
                } else {
                    mcpLastUsed[serverId] = entry.modificationDate
                }
                for projectId in entry.matchedProjectIds {
                    mcpByProject[serverId, default: [:]][projectId, default: 0] += count
                }
            }

            for (skillId, count) in entry.skillCounts {
                skillTotals[skillId, default: 0] += count
                if let existing = skillLastUsed[skillId] {
                    if entry.modificationDate > existing { skillLastUsed[skillId] = entry.modificationDate }
                } else {
                    skillLastUsed[skillId] = entry.modificationDate
                }
                for projectId in entry.matchedProjectIds {
                    skillByProject[skillId, default: [:]][projectId, default: 0] += count
                }
            }
        }

        // 1. Claude Code sessions (~/.claude/projects/<encoded-path>/*.jsonl)
        if let claudeRoot = configuration.claudeProjectsRoot,
           let projDirs = try? fm.contentsOfDirectory(
               at: claudeRoot,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            for projDir in projDirs {
                let encodedFolderName = projDir.lastPathComponent.lowercased()
                let matchedProjects = projects.filter { proj in
                    let encoded = proj.path
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: " ", with: "-")
                        .lowercased()
                    return encodedFolderName == encoded || encodedFolderName.hasSuffix("-\(proj.name.lowercased())")
                }.map(\.id)

                guard let sessionFiles = try? fm.contentsOfDirectory(
                    at: projDir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for fileURL in sessionFiles where fileURL.pathExtension == "jsonl" {
                    guard let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                          let mtime = vals.contentModificationDate,
                          mtime >= cutoffDate else { continue }
                    let size = Int64(vals.fileSize ?? 0)
                    let pathKey = fileURL.path
                    seenFilePaths.insert(pathKey)
                    sessionCount += 1

                    if let cached = transcriptCache[pathKey],
                       cached.modificationDate == mtime,
                       cached.fileSize == size {
                        merge(entry: cached)
                        continue
                    }

                    let parsed = parseClaudeTranscript(
                        at: fileURL,
                        mtime: mtime,
                        fileSize: size,
                        matchedProjectIds: matchedProjects
                    )
                    transcriptCache[pathKey] = parsed
                    merge(entry: parsed)
                }
            }
        }

        // 2. Antigravity transcripts (<brain>/<conversation-id>/.system_generated/logs/transcript.jsonl)
        for brainRoot in configuration.antigravityBrainRoots {
            guard let convDirs = try? fm.contentsOfDirectory(
                at: brainRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for convDir in convDirs {
                let transcriptURL = convDir
                    .appendingPathComponent(".system_generated/logs/transcript.jsonl")
                guard fm.fileExists(atPath: transcriptURL.path),
                      let vals = try? transcriptURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = vals.contentModificationDate,
                      mtime >= cutoffDate else { continue }
                let size = Int64(vals.fileSize ?? 0)
                let pathKey = transcriptURL.path
                seenFilePaths.insert(pathKey)
                sessionCount += 1

                if let cached = transcriptCache[pathKey],
                   cached.modificationDate == mtime,
                   cached.fileSize == size {
                    merge(entry: cached)
                    continue
                }

                let parsed = parseAntigravityTranscript(
                    at: transcriptURL,
                    mtime: mtime,
                    fileSize: size,
                    projects: projects
                )
                transcriptCache[pathKey] = parsed
                merge(entry: parsed)
            }
        }

        // Evict stale cache entries for deleted or aged-out files
        transcriptCache = transcriptCache.filter { seenFilePaths.contains($0.key) }

        var mcpUsage: [String: ResourceUsageStats] = [:]
        for (id, total) in mcpTotals {
            mcpUsage[id] = ResourceUsageStats(
                totalCalls30d: total,
                callsByProjectId: mcpByProject[id] ?? [:],
                lastUsedDate: mcpLastUsed[id]
            )
        }

        var skillUsage: [String: ResourceUsageStats] = [:]
        for (id, total) in skillTotals {
            skillUsage[id] = ResourceUsageStats(
                totalCalls30d: total,
                callsByProjectId: skillByProject[id] ?? [:],
                lastUsedDate: skillLastUsed[id]
            )
        }

        return UsageAggregation(
            mcpUsage: mcpUsage,
            skillUsage: skillUsage,
            sessionCount: sessionCount
        )
    }

    private func parseClaudeTranscript(
        at url: URL,
        mtime: Date,
        fileSize: Int64,
        matchedProjectIds: [String]
    ) -> CachedTranscriptEntry {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return CachedTranscriptEntry(
                modificationDate: mtime,
                fileSize: fileSize,
                mcpCounts: [:],
                skillCounts: [:],
                matchedProjectIds: matchedProjectIds
            )
        }

        var mcpCounts: [String: Int] = [:]
        var skillCounts: [String: Int] = [:]

        for server in Self.matches(for: Self.claudeMCPRegex, in: text) {
            mcpCounts[server, default: 0] += 1
        }
        if text.contains("\"Skill\"") {
            for skill in Self.matches(for: Self.claudeSkillRegex, in: text) {
                skillCounts[skill, default: 0] += 1
            }
        }

        return CachedTranscriptEntry(
            modificationDate: mtime,
            fileSize: fileSize,
            mcpCounts: mcpCounts,
            skillCounts: skillCounts,
            matchedProjectIds: matchedProjectIds
        )
    }

    private func parseAntigravityTranscript(
        at url: URL,
        mtime: Date,
        fileSize: Int64,
        projects: [ProjectProfile]
    ) -> CachedTranscriptEntry {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return CachedTranscriptEntry(
                modificationDate: mtime,
                fileSize: fileSize,
                mcpCounts: [:],
                skillCounts: [:],
                matchedProjectIds: []
            )
        }

        let lowered = text.lowercased()
        let matchedProjectIds = projects.compactMap { project -> String? in
            let fullPath = project.path.lowercased()
            if !fullPath.isEmpty && lowered.contains(fullPath) {
                return project.id
            }
            let slug = "/\(project.name.lowercased())/"
            if project.name.count >= 3 && lowered.contains(slug) {
                return project.id
            }
            return nil
        }

        var mcpCounts: [String: Int] = [:]
        var skillCounts: [String: Int] = [:]

        if text.contains("ServerName") {
            for server in Self.matches(for: Self.agyServerNameRegex, in: text) {
                mcpCounts[server, default: 0] += 1
            }
        }
        if text.contains("\"mcp_") {
            for server in Self.matches(for: Self.agyEagerMCPRegex, in: text) {
                mcpCounts[server, default: 0] += 1
            }
        }
        if text.contains("SKILL.md") {
            for skill in Self.matches(for: Self.agySkillPathRegex, in: text) {
                skillCounts[skill, default: 0] += 1
            }
        }

        return CachedTranscriptEntry(
            modificationDate: mtime,
            fileSize: fileSize,
            mcpCounts: mcpCounts,
            skillCounts: skillCounts,
            matchedProjectIds: matchedProjectIds
        )
    }

    // MARK: - Precompiled Regexes

    private static let claudeMCPRegex = try! NSRegularExpression(pattern: #""name"\s*:\s*"mcp__([a-zA-Z0-9_-]+)__"#)
    private static let claudeSkillRegex = try! NSRegularExpression(pattern: #""skill"\s*:\s*"([a-zA-Z0-9_.-]+)""#)
    private static let agyServerNameRegex = try! NSRegularExpression(pattern: #""ServerName"\s*:\s*"([a-zA-Z0-9_.-]+)""#)
    private static let agyEagerMCPRegex = try! NSRegularExpression(pattern: #""name"\s*:\s*"mcp_([a-zA-Z0-9_-]+?)_"#)
    private static let agySkillPathRegex = try! NSRegularExpression(pattern: #"/skills/([a-zA-Z0-9_.-]+)/SKILL\.md"#)

    private static func matches(for regex: NSRegularExpression, in text: String) -> [String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var results: [String] = []
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let captureRange = match.range(at: 1)
            if captureRange.location != NSNotFound {
                let value = ns.substring(with: captureRange)
                if !value.isEmpty {
                    results.append(value)
                }
            }
        }
        return results
    }
}
