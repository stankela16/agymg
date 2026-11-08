import SwiftUI

public struct VaultSkillsTab: View {
    @Bindable var state: AppState
    @Binding var deletionTarget: DeletionTarget?
    @Binding var editingSkill: SkillDefinition?
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var showingNewSkillSheet: Bool = false

    public init(state: AppState, deletionTarget: Binding<DeletionTarget?>, editingSkill: Binding<SkillDefinition?>) {
        self.state = state
        self._deletionTarget = deletionTarget
        self._editingSkill = editingSkill
    }

    private var skillCategories: [String] {
        var cats = Set(state.skills.map { $0.category })
        cats.insert("All")
        return ["All"] + cats.filter { $0 != "All" }.sorted()
    }

    private var categoryCounts: [String: Int] {
        var dict: [String: Int] = ["All": state.skills.count]
        for cat in skillCategories where cat != "All" {
            dict[cat] = state.skills.filter { $0.category == cat }.count
        }
        return dict
    }

    private var filteredSkills: [SkillDefinition] {
        state.skills.filter { skill in
            let matchesCategory = selectedCategory == "All" || skill.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                skill.name.localizedCaseInsensitiveContains(searchText) ||
                skill.id.localizedCaseInsensitiveContains(searchText) ||
                skill.description.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            filterBar

            if filteredSkills.isEmpty {
                emptyView
                    .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                skillsGridView
            }
        }
        .sheet(isPresented: $showingNewSkillSheet) {
            NewSkillSheet(state: state) { created in
                editingSkill = created
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            FilterChipsView(
                categories: skillCategories,
                counts: categoryCounts,
                selectedCategory: $selectedCategory,
                searchText: $searchText,
                placeholder: "Filter vault skills..."
            )
            Spacer()
            Button {
                showingNewSkillSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New Skill")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primaryContainer)
            .help("Create a new skill in Master Vault")
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var emptyView: some View {
        Group {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if state.skills.isEmpty {
                EmptyStateView.emptySkills
            } else {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: "brain.head.profile",
                    description: Text("No skills found in category \"\(selectedCategory)\".")
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var skillsGridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
            ForEach(filteredSkills) { skill in
                skillCard(for: skill)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func skillCard(for skill: SkillDefinition) -> some View {
        let isGlobal = state.globalSkillIds.contains(skill.id)
        let activeProjects = state.projects.filter { $0.enabledSkillIds.contains(skill.id) }

        return ResourceCardView(
            title: skill.name,
            subtitle: skill.id,
            summary: skill.description,
            iconName: DesignTokens.Gradients.iconForCategory(skill.category),
            badges: {
                ResourcePillBadge.category(skill.category)
                if isGlobal {
                    ResourcePillBadge.global
                        .help("Active across all workspaces (managed in Global Core)")
                }
                if !activeProjects.isEmpty {
                    ResourcePillBadge.scopedProjects(activeProjects.count)
                        .help("Active in: \(activeProjects.map(\.name).joined(separator: ", "))")
                }
                if !isGlobal && activeProjects.isEmpty {
                    ResourcePillBadge.catalogOnly
                        .help("Stored in Master Vault catalog, currently inactive globally and per-project")
                }
            },
            actions: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button { editingSkill = skill } label: { Image(systemName: "pencil.line") }
                        .buttonStyle(.borderless).help("View and edit SKILL.md")
                    Button(role: .destructive) { deletionTarget = .skill(skill) } label: {
                        Image(systemName: "trash").foregroundStyle(Color(hex: 0xF5222D))
                    }
                    .buttonStyle(.borderless).help("Uninstall skill from disk")
                }
            }
        )
        .contextMenu {
            Button { editingSkill = skill } label: { Label("View / Edit…", systemImage: "pencil.line") }
            Button { NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "") } label: { Label("Reveal in Finder", systemImage: "arrow.up.forward.app") }
            Divider()
            Button(role: .destructive) { deletionTarget = .skill(skill) } label: { Label("Uninstall from Mac…", systemImage: "trash") }
        }
    }
}
