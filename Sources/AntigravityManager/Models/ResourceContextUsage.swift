import Foundation

public enum ContextHealthLevel: String, Sendable, Equatable, CaseIterable {
    case clean = "Clean"
    case heavy = "Heavy"
    case bloated = "Bloated"

    public var badgeLabel: String { rawValue }
}

public struct ResourceFootprint: Equatable, Sendable {
    public let antigravityStartupTokens: Int
    public let claudeStartupTokens: Int
    public let onDemandTokens: Int
    public let toolCount: Int

    public init(
        antigravityStartupTokens: Int,
        claudeStartupTokens: Int,
        onDemandTokens: Int,
        toolCount: Int = 0
    ) {
        self.antigravityStartupTokens = antigravityStartupTokens
        self.claudeStartupTokens = claudeStartupTokens
        self.onDemandTokens = onDemandTokens
        self.toolCount = toolCount
    }

    public static let zero = ResourceFootprint(
        antigravityStartupTokens: 0,
        claudeStartupTokens: 0,
        onDemandTokens: 0,
        toolCount: 0
    )

    public static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000 {
            let k = Double(tokens) / 1_000.0
            return String(format: "%.1fk", k)
        }
        return "\(tokens)"
    }
}

public struct ResourceUsageStats: Equatable, Sendable {
    public let totalCalls30d: Int
    public let callsByProjectId: [String: Int]
    public let lastUsedDate: Date?

    public init(
        totalCalls30d: Int = 0,
        callsByProjectId: [String: Int] = [:],
        lastUsedDate: Date? = nil
    ) {
        self.totalCalls30d = totalCalls30d
        self.callsByProjectId = callsByProjectId
        self.lastUsedDate = lastUsedDate
    }

    public static let empty = ResourceUsageStats()

    public func calls(inProject projectId: String) -> Int {
        callsByProjectId[projectId] ?? 0
    }

    public var usedProjectIds: [String] {
        callsByProjectId
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)
    }
}

public struct WorkspaceContextSummary: Equatable, Sendable {
    public let health: ContextHealthLevel
    public let antigravityStartupTokens: Int
    public let claudeStartupTokens: Int
    public let activeMCPCount: Int
    public let activeSkillCount: Int
    public let dormantProjectMCPIds: [String]
    public let dormantProjectSkillIds: [String]
    public let dormantGlobalMCPIds: [String]
    public let dormantGlobalSkillIds: [String]

    public var totalDormantCount: Int {
        dormantProjectMCPIds.count
            + dormantProjectSkillIds.count
            + dormantGlobalMCPIds.count
            + dormantGlobalSkillIds.count
    }

    public var dormantProjectTotalCount: Int {
        dormantProjectMCPIds.count + dormantProjectSkillIds.count
    }

    public var formattedAntigravityTokens: String {
        ResourceFootprint.formatTokens(antigravityStartupTokens)
    }

    public var formattedClaudeTokens: String {
        ResourceFootprint.formatTokens(claudeStartupTokens)
    }

    public static let empty = WorkspaceContextSummary(
        health: .clean,
        antigravityStartupTokens: 0,
        claudeStartupTokens: 0,
        activeMCPCount: 0,
        activeSkillCount: 0,
        dormantProjectMCPIds: [],
        dormantProjectSkillIds: [],
        dormantGlobalMCPIds: [],
        dormantGlobalSkillIds: []
    )
}

public struct ContextUsageSnapshot: Equatable, Sendable {
    public let mcpFootprints: [String: ResourceFootprint]
    public let skillFootprints: [String: ResourceFootprint]
    public let mcpUsage: [String: ResourceUsageStats]
    public let skillUsage: [String: ResourceUsageStats]
    public let scannedSessionsCount: Int
    public let lastUpdated: Date

    public init(
        mcpFootprints: [String: ResourceFootprint] = [:],
        skillFootprints: [String: ResourceFootprint] = [:],
        mcpUsage: [String: ResourceUsageStats] = [:],
        skillUsage: [String: ResourceUsageStats] = [:],
        scannedSessionsCount: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.mcpFootprints = mcpFootprints
        self.skillFootprints = skillFootprints
        self.mcpUsage = mcpUsage
        self.skillUsage = skillUsage
        self.scannedSessionsCount = scannedSessionsCount
        self.lastUpdated = lastUpdated
    }

    public static let empty = ContextUsageSnapshot(lastUpdated: .distantPast)

    public func mcpStats(for id: String) -> ResourceUsageStats {
        mcpUsage[id] ?? .empty
    }

    public func skillStats(for id: String) -> ResourceUsageStats {
        skillUsage[id] ?? .empty
    }

    public func mcpFootprint(for id: String) -> ResourceFootprint {
        mcpFootprints[id] ?? .zero
    }

    public func skillFootprint(for id: String) -> ResourceFootprint {
        skillFootprints[id] ?? .zero
    }

    /// Pure, zero-I/O computation safe to call from SwiftUI or AppState.
    public func summary(
        for project: ProjectProfile?,
        globalServerIds: Set<String>,
        globalSkillIds: Set<String>
    ) -> WorkspaceContextSummary {
        let projectMCPs = project?.enabledMCPServerIds ?? []
        let projectSkills = project?.enabledSkillIds ?? []

        let activeMCPs = globalServerIds.union(projectMCPs)
        let activeSkills = globalSkillIds.union(projectSkills)

        var agyTokens = 0
        var ccTokens = 0

        var dormantProjectMCPs: [String] = []
        var dormantGlobalMCPs: [String] = []
        for id in activeMCPs.sorted() {
            let fp = mcpFootprint(for: id)
            agyTokens += fp.antigravityStartupTokens
            ccTokens += fp.claudeStartupTokens

            let stats = mcpStats(for: id)
            let calls = project.map { stats.calls(inProject: $0.id) } ?? stats.totalCalls30d
            if calls == 0 {
                if globalServerIds.contains(id) {
                    dormantGlobalMCPs.append(id)
                } else {
                    dormantProjectMCPs.append(id)
                }
            }
        }

        var dormantProjectSkills: [String] = []
        var dormantGlobalSkills: [String] = []
        for id in activeSkills.sorted() {
            let fp = skillFootprint(for: id)
            agyTokens += fp.antigravityStartupTokens
            ccTokens += fp.claudeStartupTokens

            let stats = skillStats(for: id)
            let calls = project.map { stats.calls(inProject: $0.id) } ?? stats.totalCalls30d
            if calls == 0 {
                if globalSkillIds.contains(id) {
                    dormantGlobalSkills.append(id)
                } else {
                    dormantProjectSkills.append(id)
                }
            }
        }

        let totalDormant = dormantProjectMCPs.count
            + dormantGlobalMCPs.count
            + dormantProjectSkills.count
            + dormantGlobalSkills.count

        let health: ContextHealthLevel
        if totalDormant >= 6 || ccTokens >= 25_000 || agyTokens >= 3_500 {
            health = .bloated
        } else if totalDormant >= 3 || ccTokens >= 12_000 || agyTokens >= 2_000 {
            health = .heavy
        } else {
            health = .clean
        }

        return WorkspaceContextSummary(
            health: health,
            antigravityStartupTokens: agyTokens,
            claudeStartupTokens: ccTokens,
            activeMCPCount: activeMCPs.count,
            activeSkillCount: activeSkills.count,
            dormantProjectMCPIds: dormantProjectMCPs,
            dormantProjectSkillIds: dormantProjectSkills,
            dormantGlobalMCPIds: dormantGlobalMCPs,
            dormantGlobalSkillIds: dormantGlobalSkills
        )
    }
}
