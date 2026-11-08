import SwiftUI

public struct ProjectIsolationSidebarView: View {
    public let project: ProjectProfile
    public let state: AppState

    public init(project: ProjectProfile, state: AppState) {
        self.project = project
        self.state = state
    }

    private var audit: ProjectSafetyAudit {
        state.safetyAudit(for: project)
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            isolationDiagramCard
            linkedSkillsCard
            gitSafetyAuditCard
        }
        .frame(width: 280)
        .task(id: project.id) {
            await state.refreshSafetyAudit(for: project)
        }
        .task(id: state.lastSyncDate) {
            await state.refreshSafetyAudit(for: project)
        }
    }

    private var isolationDiagramCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Runtime Isolation")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Image(systemName: icon(for: audit.overallStatus))
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor(for: audit.overallStatus))
                    .help(audit.overallStatus == .passed ? "Workspace is safely isolated" : "Isolation requires inspection")
            }

            Text("Master Vault resources are safely linked via symlinks into the project sandbox.")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.inkSecondary)

            // Step 1
            diagramStep(number: "1", title: "Master Vault", subtitle: "~/.gemini/manager-vault/", icon: "lock.shield")
            // Step 2
            diagramStep(number: "2", title: "Atomic Symlink Engine", subtitle: "Non-destructive references", icon: "arrow.triangle.2.circlepath")
            // Step 3
            diagramStep(number: "3", title: "Isolated Project Runtime", subtitle: ".agents/plugins/agy-manager/", icon: "folder.badge.gearshape")
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private func diagramStep(number: String, title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs)
                    .fill(DesignTokens.surfaceContainer)
                    .frame(width: 20, height: 20)
                Text(number)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(DesignTokens.ink)
                Text(subtitle).font(.system(size: 9, design: .monospaced)).foregroundStyle(DesignTokens.inkTertiary)
            }
            Spacer()
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(DesignTokens.secondary)
        }
        .padding(DesignTokens.Spacing.xxs)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
    }

    private var linkedSkillsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.secondary)
                    Text("Linked Skills (\(project.enabledSkillIds.count) Active)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                Text("+ Link Skill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.secondary)
            }

            VStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(Array(project.enabledSkillIds.prefix(4)), id: \.self) { skillId in
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Circle().fill(DesignTokens.secondary).frame(width: 5, height: 5)
                        Text(skillId).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DesignTokens.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("Active").font(.system(size: 8.5, design: .monospaced)).foregroundStyle(DesignTokens.secondary)
                    }
                }
                if project.enabledSkillIds.isEmpty {
                    Text("No linked skills.").font(.system(size: 9.5)).foregroundStyle(DesignTokens.inkTertiary)
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private var gitSafetyAuditCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor(for: audit.overallStatus))
                    Text("Git & Safety Audits")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.ink)
                }
                Spacer()
                statusBadge(for: audit.overallStatus)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(audit.items) { item in
                    auditRow(item)
                }
            }

            if audit.overallStatus != .passed {
                Button {
                    state.syncProject(project)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync & Protect")
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .padding(.top, DesignTokens.Spacing.xxs)
                .help("Runs automatic synchronization to update .gitignore rules and reconcile manifests")
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(cardBorder(for: audit.overallStatus), lineWidth: 1)
        )
    }

    private func auditRow(_ item: ProjectSafetyAudit.AuditItem) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: icon(for: item.status))
                .font(.system(size: 10))
                .foregroundStyle(statusColor(for: item.status))
                .frame(width: 14, height: 14, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.ink)

                Text(item.detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .help(item.detail)
    }

    private func statusBadge(for status: ProjectSafetyAudit.AuditStatus) -> some View {
        Text(status.title)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(statusColor(for: status))
            .padding(.horizontal, DesignTokens.Spacing.xxs)
            .padding(.vertical, 2)
            .background(statusColor(for: status).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func statusColor(for status: ProjectSafetyAudit.AuditStatus) -> Color {
        switch status {
        case .passed:
            return DesignTokens.secondary
        case .warning:
            return DesignTokens.tierOrange
        case .failed:
            return DesignTokens.Colors.statusError
        case .checking:
            return DesignTokens.steel
        }
    }

    private func icon(for status: ProjectSafetyAudit.AuditStatus) -> String {
        switch status {
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .checking:
            return "hourglass"
        }
    }

    private func cardBorder(for status: ProjectSafetyAudit.AuditStatus) -> Color {
        switch status {
        case .failed:
            return DesignTokens.Colors.statusError.opacity(0.3)
        case .warning:
            return DesignTokens.tierOrange.opacity(0.3)
        default:
            return DesignTokens.cardBorder
        }
    }
}
