import SwiftUI
import AppKit

public struct MenuBarSkillRow: View {
    @Bindable var state: AppState
    let skill: SkillDefinition
    let projectId: String?
    let isLocalProjectSkill: Bool
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    @State private var isHovered: Bool = false

    public init(
        state: AppState,
        skill: SkillDefinition,
        projectId: String? = nil,
        isLocalProjectSkill: Bool = false,
        isExpanded: Bool = false,
        onToggleExpand: (() -> Void)? = nil
    ) {
        self.state = state
        self.skill = skill
        self.projectId = projectId
        self.isLocalProjectSkill = isLocalProjectSkill
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                rowHeaderButton
                toggleControl
            }

            if isExpanded {
                expandedDetailView
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(isExpanded ? DesignTokens.surfaceContainerLow : (isHovered ? DesignTokens.surfaceContainerHigh : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isExpanded ? DesignTokens.cardBorder : Color.clear, lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .task(id: isExpanded) {
            if isExpanded {
                state.loadSkillPreviewIfNeeded(for: skill)
            }
        }
    }

    @ViewBuilder
    private var rowHeaderButton: some View {
        if let onToggleExpand {
            Button(action: onToggleExpand) {
                headerRowLabel
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(skill.name) details" : "Inspect \(skill.name) instructions before toggling")
            .accessibilityLabel("\(skill.name), \(isExpanded ? "collapse details" : "show details")")
        } else {
            headerRowLabel
        }
    }

    private var headerRowLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(isEnabled ? DesignTokens.Colors.statusSuccess : DesignTokens.inkTertiary.opacity(0.4))
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

                    if onToggleExpand != nil && (isHovered || isExpanded) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignTokens.inkTertiary)
                    }
                }

                if !isExpanded {
                    Text(skillSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var expandedDetailView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Text(skill.category)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(DesignTokens.storeBlueTint)
                    .clipShape(Capsule())

                Text(skill.id)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = state.skillPreviews[skill.id], !preview.isEmpty, preview != skill.description {
                Text(preview)
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(DesignTokens.Spacing.xxs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.surfaceContainerLowest)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if state.skillPreviews[skill.id] == nil {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading SKILL.md preview…")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                Button {
                    state.openSkillInControlCenter(skill)
                } label: {
                    Label("Edit SKILL.md", systemImage: "doc.text")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Open full SKILL.md in Control Center editor")

                Button {
                    NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Finder", systemImage: "folder")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Reveal skill directory in Finder")

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.leading, 14)
        .padding(.bottom, DesignTokens.Spacing.xxs)
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
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    @State private var isHovered: Bool = false

    public init(
        state: AppState,
        plugin: PluginDefinition,
        projectId: String? = nil,
        isExpanded: Bool = false,
        onToggleExpand: (() -> Void)? = nil
    ) {
        self.state = state
        self.plugin = plugin
        self.projectId = projectId
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                rowHeaderButton
                toggleControl
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        if plugin.hasMCP {
                            Text("Includes MCP")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(DesignTokens.storeBlueTint)
                                .clipShape(Capsule())
                        }
                        if plugin.hasSkills {
                            Text("Bundled Skills")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.tierOrange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(DesignTokens.tierOrange.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 0)
                    }

                    Text(plugin.description.isEmpty ? "Managed plugin bundle in Master Vault." : plugin.description)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Reveal plugin folder in Finder")
                }
                .padding(.leading, 14)
                .padding(.bottom, DesignTokens.Spacing.xxs)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(isExpanded ? DesignTokens.surfaceContainerLow : (isHovered ? DesignTokens.surfaceContainerHigh : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isExpanded ? DesignTokens.cardBorder : Color.clear, lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var rowHeaderButton: some View {
        if let onToggleExpand {
            Button(action: onToggleExpand) {
                headerLabel
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(plugin.name) details" : "Inspect \(plugin.name) package contents")
        } else {
            headerLabel
        }
    }

    private var headerLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(isEnabled ? DesignTokens.Colors.statusSuccess : DesignTokens.inkTertiary.opacity(0.4))
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

                    if onToggleExpand != nil && (isHovered || isExpanded) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignTokens.inkTertiary)
                    }
                }

                if !isExpanded {
                    Text(plugin.description)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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
