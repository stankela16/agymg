import SwiftUI

public struct MenuBarSkillRow: View {
    @Bindable var state: AppState
    let skill: SkillDefinition
    let projectId: String?
    let isLocalProjectSkill: Bool
    @State private var isHovered: Bool = false

    public init(
        state: AppState,
        skill: SkillDefinition,
        projectId: String? = nil,
        isLocalProjectSkill: Bool = false
    ) {
        self.state = state
        self.skill = skill
        self.projectId = projectId
        self.isLocalProjectSkill = isLocalProjectSkill
    }

    private var project: ProjectProfile? {
        guard let projectId else { return nil }
        return state.projects.first(where: { $0.id == projectId })
    }

    private var isGlobal: Bool {
        state.globalSkillIds.contains(skill.id)
    }

    private var isProjectEnabled: Bool {
        if isLocalProjectSkill { return true }
        return project?.enabledSkillIds.contains(skill.id) ?? false
    }

    private var isEnabled: Bool {
        if projectId != nil {
            return isGlobal || isProjectEnabled
        } else {
            return isGlobal
        }
    }

    private var isInheritedGlobal: Bool {
        projectId != nil && isGlobal && !isLocalProjectSkill
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(isEnabled ? Color.green : DesignTokens.inkTertiary.opacity(0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(skill.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.ink)
                        .lineLimit(1)

                    if isLocalProjectSkill {
                        Text("LOCAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.secondary.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Local project skill in .agents/skills")
                    } else if isInheritedGlobal {
                        Text("GLOBAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.tierOrange)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.tierOrange.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Inherited from Global Core (active across all workspaces)")
                    } else if projectId != nil && isProjectEnabled {
                        Text("PROJECT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.secondary.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Locally enabled for this project")
                    }
                }

                Text(skillSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .lineLimit(1)
            }

            Spacer()

            toggleControl
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(isHovered ? DesignTokens.surfaceContainerHigh : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var skillSubtitle: String {
        let base = skill.description.isEmpty ? skill.category : skill.description
        if isLocalProjectSkill {
            return "Repo skill • \(base)"
        }
        if isInheritedGlobal {
            return "Inherited • \(base)"
        }
        return base
    }

    @ViewBuilder
    private var toggleControl: some View {
        if isLocalProjectSkill {
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(true)
                .help("\(skill.name) is a local skill committed inside the project repository")
        } else if isInheritedGlobal {
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(true)
                .help("\(skill.name) is enabled globally via Global Core (inherited)")
        } else if let pId = projectId {
            Toggle("", isOn: Binding(
                get: { isProjectEnabled },
                set: { _ in state.toggleProjectSkill(projectId: pId, skillId: skill.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(isProjectEnabled ? "Disable \(skill.name) for this project" : "Enable \(skill.name) for project \(project?.name ?? "")")
        } else {
            Toggle("", isOn: Binding(
                get: { isGlobal },
                set: { _ in state.toggleGlobalSkill(id: skill.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(isGlobal ? "Disable \(skill.name) in Global Core" : "Enable \(skill.name) in Global Core")
        }
    }
}

public struct MenuBarPluginRow: View {
    @Bindable var state: AppState
    let plugin: PluginDefinition
    let projectId: String?
    @State private var isHovered: Bool = false

    public init(state: AppState, plugin: PluginDefinition, projectId: String? = nil) {
        self.state = state
        self.plugin = plugin
        self.projectId = projectId
    }

    private var project: ProjectProfile? {
        guard let projectId else { return nil }
        return state.projects.first(where: { $0.id == projectId })
    }

    private var isGlobal: Bool {
        state.globalPluginIds.contains(plugin.id)
    }

    private var isProjectEnabled: Bool {
        project?.enabledPluginIds.contains(plugin.id) ?? false
    }

    private var isEnabled: Bool {
        if projectId != nil {
            return isGlobal || isProjectEnabled
        } else {
            return isGlobal
        }
    }

    private var isInheritedGlobal: Bool {
        projectId != nil && isGlobal
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(isEnabled ? Color.green : DesignTokens.inkTertiary.opacity(0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(plugin.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.ink)
                        .lineLimit(1)

                    if isInheritedGlobal {
                        Text("GLOBAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.tierOrange)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.tierOrange.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Inherited from Global Core")
                    } else if projectId != nil && isProjectEnabled {
                        Text("PROJECT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.secondary.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Enabled for this project")
                    }
                }

                Text(plugin.description)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .lineLimit(1)
            }

            Spacer()

            toggleControl
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(isHovered ? DesignTokens.surfaceContainerHigh : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var toggleControl: some View {
        if isInheritedGlobal {
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(true)
                .help("\(plugin.name) is enabled globally via Global Core")
        } else if let pId = projectId {
            Toggle("", isOn: Binding(
                get: { isProjectEnabled },
                set: { _ in state.toggleProjectPlugin(projectId: pId, pluginId: plugin.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(isProjectEnabled ? "Disable \(plugin.name) for this project" : "Enable \(plugin.name) for project \(project?.name ?? "")")
        } else {
            Toggle("", isOn: Binding(
                get: { isGlobal },
                set: { _ in state.toggleGlobalPlugin(id: plugin.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(isGlobal ? "Disable \(plugin.name) in Global Core" : "Enable \(plugin.name) in Global Core")
        }
    }
}
