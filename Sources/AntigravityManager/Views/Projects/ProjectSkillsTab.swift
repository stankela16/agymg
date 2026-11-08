import SwiftUI
import AppKit

public struct ProjectSkillsTab: View {
    @Bindable var state: AppState
    let projectId: String
    @Binding var deletionTarget: DeletionTarget?
    @Binding var editingSkill: SkillDefinition?
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

    private let categories = ["All", "Swift & Apple", "Video & Remotion", "Multi-Agent & Review", "Web & Frontend", "System & Engine", "Core & Tools"]

    public init(
        state: AppState,
        projectId: String,
        deletionTarget: Binding<DeletionTarget?>,
        editingSkill: Binding<SkillDefinition?>
    ) {
        self.state = state
        self.projectId = projectId
        self._deletionTarget = deletionTarget
        self._editingSkill = editingSkill
    }

    public init(
        state: AppState,
        project: ProjectProfile,
        deletionTarget: Binding<DeletionTarget?>,
        editingSkill: Binding<SkillDefinition?>
    ) {
        self.state = state
        self.projectId = project.id
        self._deletionTarget = deletionTarget
        self._editingSkill = editingSkill
    }

    private var project: ProjectProfile? {
        state.projects.first(where: { $0.id == projectId })
    }

    private var projectLocals: [SkillDefinition] {
        guard let project = project else { return [] }
        let vaultIds = Set(state.skills.map(\.id))
        return state.localSkills(for: project).filter { !vaultIds.contains($0.id) }
    }
    private var filteredLocals: [SkillDefinition] { filterList(projectLocals) }
    private var filteredVaultSkills: [SkillDefinition] { filterList(state.skills) }

    private var categoryCounts: [String: Int] {
        var seen = Set<String>()
        let allSkills = (projectLocals + state.skills).filter { seen.insert($0.id).inserted }
        var dict: [String: Int] = ["All": allSkills.count]
        for cat in categories where cat != "All" {
            dict[cat] = allSkills.filter { $0.category == cat }.count
        }
        return dict
    }

    private func filterList(_ list: [SkillDefinition]) -> [SkillDefinition] {
        list.filter { skill in
            let matchesCategory = selectedCategory == "All" || skill.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                skill.name.localizedCaseInsensitiveContains(searchText) ||
                skill.id.localizedCaseInsensitiveContains(searchText) ||
                skill.description.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        let locals = filteredLocals
        let vault = filteredVaultSkills
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            filterBar
            if locals.isEmpty && vault.isEmpty {
                emptyView
                    .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                cardsGridView(locals: locals, vaultSkills: vault)
            }
        }
    }

    private var filterBar: some View {
        FilterChipsView(
            categories: categories,
            counts: categoryCounts,
            selectedCategory: $selectedCategory,
            searchText: $searchText,
            placeholder: "Filter skills..."
        )
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var emptyView: some View {
        Group {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView("No Skills", systemImage: "sparkles", description: Text("No local or Master Vault skills found."))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cardsGridView(locals: [SkillDefinition], vaultSkills: [SkillDefinition]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if !locals.isEmpty {
                sectionHeader("Local in Repository (\(locals.count))")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
                    ForEach(locals) { localCard(for: $0) }
                }
            }

            sectionHeader("Master Vault Catalog (\(vaultSkills.count))")
            if vaultSkills.isEmpty {
                Text("No skills available in Master Vault.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.inkSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
                    ForEach(vaultSkills) { vaultCard(for: $0) }
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(DesignTokens.ink)
            .padding(.top, DesignTokens.Spacing.xs)
    }

    private func localCard(for skill: SkillDefinition) -> some View {
        ResourceCardView(
            title: skill.name,
            subtitle: skill.path,
            summary: skill.description,
            iconName: DesignTokens.Gradients.iconForCategory(skill.category),
            badges: {
                ResourcePillBadge(title: "LOCAL", color: DesignTokens.primary, backgroundColor: DesignTokens.storeBlueTint)
            },
            actions: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button { editingSkill = skill } label: { Label("Edit", systemImage: "pencil.line") }
                        .buttonStyle(.bordered).controlSize(.small).help("View and edit SKILL.md")
                    Button { NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "") } label: { Image(systemName: "arrow.up.forward.app") }
                        .buttonStyle(.borderless).help("Reveal in Finder")
                }
            }
        )
    }

    private func vaultCard(for skill: SkillDefinition) -> some View {
        let isGlobal = state.globalSkillIds.contains(skill.id)
        let isProjectEnabled = project?.enabledSkillIds.contains(skill.id) ?? false

        return ResourceCardView(
            title: skill.name,
            subtitle: skill.id,
            summary: skill.description,
            iconName: DesignTokens.Gradients.iconForCategory(skill.category),
            badges: {
                if isGlobal {
                    ResourcePillBadge.global
                        .help("Already enabled globally across all workspaces via Global Core")
                }
                if isProjectEnabled {
                    ResourcePillBadge.linkedToProject
                        .help("Linked to this project via .agents/skills/ and .claude/skills/")
                }
            },
            actions: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button { editingSkill = skill } label: { Image(systemName: "pencil.line") }
                        .buttonStyle(.borderless).help("View and edit SKILL.md")
                    if isGlobal {
                        Toggle("", isOn: .constant(true))
                            .labelsHidden().toggleStyle(.switch)
                            .tint(DesignTokens.primaryContainer)
                            .disabled(true)
                            .help("Enabled globally via Global Core (available across all projects). Manage in Global Core.")
                    } else {
                        Toggle("", isOn: Binding(
                            get: { project?.enabledSkillIds.contains(skill.id) ?? false },
                            set: { _ in state.toggleProjectSkill(projectId: projectId, skillId: skill.id) }
                        ))
                        .labelsHidden().toggleStyle(.switch)
                        .tint(DesignTokens.primaryContainer)
                        .help(isProjectEnabled ? "Unlink skill from project" : "Link skill to project")
                    }
                }
            }
        )
    }
}
