import SwiftUI

public struct ProjectRecommendationsCard: View {
    @Bindable var state: AppState
    let projectId: String

    public init(state: AppState, projectId: String) {
        self.state = state
        self.projectId = projectId
    }

    private var recommendations: [ResourceRecommendation] {
        state.projectRecommendations[projectId] ?? []
    }

    private var stackLabels: [String] {
        state.projectStackLabels[projectId] ?? []
    }

    private var dismissedCount: Int {
        state.dismissedRecommendationCount(for: projectId)
    }

    private var essentialRecommendations: [ResourceRecommendation] {
        recommendations.filter { $0.priority == .high }
    }

    public var body: some View {
        if !recommendations.isEmpty {
            activeRecommendationsCard
        } else if dismissedCount > 0 {
            dismissedNoticeBanner
        }
    }

    private var activeRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DesignTokens.tierOrange)

                Text("SUGGESTED FOR REPO (\(recommendations.count))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.ink)

                ForEach(stackLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.tierOrange)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(DesignTokens.tierOrange.opacity(0.14))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                if dismissedCount > 0 {
                    Button {
                        state.resetDismissedRecommendations(for: projectId)
                    } label: {
                        Text("Restore \(dismissedCount) dismissed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.inkSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .help("Restore \(dismissedCount) previously dismissed suggestion(s)")
                }

                if !essentialRecommendations.isEmpty && essentialRecommendations.count < recommendations.count {
                    Button {
                        state.enableRecommendations(essentialRecommendations, for: projectId)
                    } label: {
                        Text("Enable Essential (\(essentialRecommendations.count))")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Enable \(essentialRecommendations.count) essential stack tools: \(essentialRecommendations.map(\.name).joined(separator: ", "))")
                }

                if recommendations.count > 1 {
                    Button {
                        state.enableAllRecommendations(for: projectId)
                    } label: {
                        Text("Enable All (\(recommendations.count))")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.primaryContainer)
                    .controlSize(.small)
                    .help("Enable all \(recommendations.count) recommended tools for this project")
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignTokens.Spacing.xs)],
                spacing: DesignTokens.Spacing.xs
            ) {
                ForEach(recommendations, id: \.uniqueKey) { rec in
                    recommendationCard(rec)
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.tierOrange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.tierOrange.opacity(0.28), lineWidth: 1)
        )
    }

    private var dismissedNoticeBanner: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.inkSecondary)

            Text("\(dismissedCount) stack recommendation(s) dismissed for this repository.")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.inkSecondary)

            Spacer(minLength: 0)

            Button {
                state.resetDismissedRecommendations(for: projectId)
            } label: {
                Text("Restore Dismissed")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Show dismissed Vault recommendations again")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private func recommendationCard(_ rec: ResourceRecommendation) -> some View {
        let priorityLabel: String
        let priorityColor: Color
        switch rec.priority {
        case .high:
            priorityLabel = "ESSENTIAL"
            priorityColor = DesignTokens.secondary
        case .medium:
            priorityLabel = "RECOMMENDED"
            priorityColor = DesignTokens.tierOrange
        case .low:
            priorityLabel = "OPTIONAL"
            priorityColor = DesignTokens.inkTertiary
        }

        return HStack(spacing: DesignTokens.Spacing.xs) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(rec.kind.displayLabel)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.tierOrange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(DesignTokens.tierOrange.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))

                    Text(priorityLabel)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(priorityColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(priorityColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
                }

                Text(rec.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
                    .lineLimit(1)

                Text(rec.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xxs) {
                Button {
                    state.dismissRecommendation(rec, for: projectId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .frame(width: 20, height: 20)
                        .background(DesignTokens.surfaceContainerLow)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss \(rec.name) suggestion for this project")

                Button {
                    state.enableRecommendedResource(rec, for: projectId)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Enable")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Enable \(rec.name) (\(rec.kind.displayLabel)) for this project")
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }
}
