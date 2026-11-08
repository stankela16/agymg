import SwiftUI
import AppKit

public struct GlobalCoreSkillsTab: View {
    @Bindable var state: AppState
    @Binding var deletionTarget: DeletionTarget?
    @Binding var editingSkill: SkillDefinition?
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

    public init(
        state: AppState,
        deletionTarget: Binding<DeletionTarget?>,
        editingSkill: Binding<SkillDefinition?>
    ) {
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
    }

    private var filterBar: some View {
        FilterChipsView(
            categories: skillCategories,
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
                ContentUnavailableView(
                    "No Global Skills",
                    systemImage: "brain.head.profile",
                    description: Text("No global skills found in this category.")
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
        let isActive = state.globalSkillIds.contains(skill.id)

        return ResourceCardView(
            title: skill.name,
            subtitle: skill.id,
            summary: skill.description,
            iconName: DesignTokens.Gradients.iconForCategory(skill.category),
            badges: {
                if isActive { ResourcePillBadge.global }
            },
            actions: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button { editingSkill = skill } label: { Image(systemName: "pencil.line") }
                        .buttonStyle(.borderless).help("View and edit SKILL.md")
                    Toggle("", isOn: Binding(
                        get: { isActive },
                        set: { _ in state.toggleGlobalSkill(id: skill.id) }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .tint(DesignTokens.primaryContainer)
                    .help(isActive ? "Disable global skill" : "Enable global skill")
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
