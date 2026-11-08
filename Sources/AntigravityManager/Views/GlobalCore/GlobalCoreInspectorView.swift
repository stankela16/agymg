import SwiftUI

public struct GlobalCoreInspectorView: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 12) {
            globalScopeCard
            tokenOptimizationCard
            inheritedProjectsCard
            syncStatusCard
        }
        .frame(width: 280)
    }

    private var globalScopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.tierOrange)
                    Text("Global Scope Paths")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.tierOrange)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(DesignTokens.tierOrange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            VStack(alignment: .leading, spacing: 6) {
                pathRow(label: "MCP Config", path: "~/.gemini/config/mcp_config.json")
                pathRow(label: "Skills Root", path: "~/.gemini/config/skills/")
                pathRow(label: "Plugins Root", path: "~/.gemini/config/plugins/")
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkTertiary)
                Text("Active tools are automatically written to these paths.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.inkTertiary)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var tokenOptimizationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.badge.clock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Token Optimization")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text("TIP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(DesignTokens.secondaryContainer.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Text("Every active global tool is loaded into the system prompt of every new chat. Keep only universal tools here (e.g., GitHub, ask, code review) and scope specialized tools to individual projects.")
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var inheritedProjectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.primary)
                    Text("Inherited by All Projects")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text("\(state.projects.count) projects")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)
            }

            VStack(spacing: 6) {
                ForEach(state.projects.prefix(4)) { project in
                    HStack(spacing: 6) {
                        Circle().fill(DesignTokens.secondary).frame(width: 5, height: 5)
                        Text(project.name).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("+\(state.globalServerIds.count) Global")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkTertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Sync Engine Status")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text(state.isSyncing ? "SYNCING" : "SYNCED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.isSyncing ? DesignTokens.tierOrange : DesignTokens.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(
                        (state.isSyncing ? DesignTokens.tierOrange : DesignTokens.secondary)
                            .opacity(0.15)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Active servers:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text("\(state.globalServerIds.count) / \(state.servers.count)").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.inkSecondary)
                }
                HStack {
                    Text("Active skills:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text("\(state.globalSkillIds.count) / \(state.skills.count)").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.inkSecondary)
                }
                HStack {
                    Text("Last sync:").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                    Spacer()
                    Text(state.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "Not synced").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.secondary)
                }
            }
        }
        .padding(12)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
    }

    private func pathRow(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(DesignTokens.inkTertiary)
            Text(path).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(DesignTokens.inkSecondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}
