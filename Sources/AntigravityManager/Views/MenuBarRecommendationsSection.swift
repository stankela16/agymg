import SwiftUI

public struct MenuBarRecommendationsSection: View {
    @Bindable var state: AppState
    let projectId: String
    let recommendations: [ResourceRecommendation]
    let stackLabels: [String]

    public init(
        state: AppState,
        projectId: String,
        recommendations: [ResourceRecommendation],
        stackLabels: [String] = []
    ) {
        self.state = state
        self.projectId = projectId
        self.recommendations = recommendations
        self.stackLabels = stackLabels
    }

    public var body: some View {
        if recommendations.isEmpty {
            allActiveBanner
        } else {
            missingRecommendationsCard
        }
    }

    private var stackBadgeText: String {
        stackLabels.isEmpty ? "Repo Stack" : stackLabels.joined(separator: " · ")
    }

    private var hasAnyProjectSpecificResources: Bool {
        guard let proj = state.projects.first(where: { $0.id == projectId }) else { return false }
        let localSkills = state.projectLocalSkills[projectId] ?? []
        return !proj.enabledMCPServerIds.isEmpty
            || !proj.enabledSkillIds.isEmpty
            || !proj.enabledPluginIds.isEmpty
            || !localSkills.isEmpty
    }

    private var allActiveBanner: some View {
        let isConfigured = hasAnyProjectSpecificResources
        return HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: isConfigured ? "checkmark.seal.fill" : "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isConfigured ? Color.green : DesignTokens.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text("SUGGESTED FOR REPO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.inkSecondary)

                    Text(stackBadgeText)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondary)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(DesignTokens.storeBlueTint)
                        .clipShape(Capsule())
                }

                Text(isConfigured
                     ? "All recommended Vault tools for this stack are active"
                     : "No project tools active — select MCP/Skills below")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(isConfigured ? Color.green.opacity(0.25) : DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private var missingRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.tierOrange)

                Text("SUGGESTED FOR REPO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkSecondary)

                if !stackLabels.isEmpty {
                    Text(stackBadgeText)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.tierOrange)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(DesignTokens.tierOrange.opacity(0.14))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                Spacer()

                if recommendations.count > 1 {
                    Button {
                        state.enableAllRecommendations(for: projectId)
                    } label: {
                        Text("Enable All (\(recommendations.count))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 2)
                            .background(DesignTokens.storeBlueTint)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Enable all recommended tools for this project at once")
                }
            }

            VStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(Array(recommendations.prefix(3)), id: \.uniqueKey) { rec in
                    recommendationRow(rec)
                }
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.tierOrange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.tierOrange.opacity(0.28), lineWidth: 1)
        )
    }

    private func recommendationRow(_ rec: ResourceRecommendation) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(rec.kind.displayLabel)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.tierOrange)
                .padding(.horizontal, DesignTokens.Spacing.xxs)
                .padding(.vertical, 2)
                .background(DesignTokens.tierOrange.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))

            VStack(alignment: .leading, spacing: 1) {
                Text(rec.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
                    .lineLimit(1)

                Text(rec.reason)
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                state.enableRecommendedResource(rec, for: projectId)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Enable")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.secondary)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.surfaceContainerLowest)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(DesignTokens.secondary.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Enable \(rec.name) (\(rec.kind.displayLabel)) for the active project")
        }
    }
}
