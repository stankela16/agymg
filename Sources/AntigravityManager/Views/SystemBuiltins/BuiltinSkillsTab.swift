import SwiftUI
import AppKit

public struct BuiltinSkillsTab: View {
    public let skills: [SkillDefinition]
    @Binding var editingSkill: SkillDefinition?
    public var searchText: String

    public init(
        skills: [SkillDefinition],
        editingSkill: Binding<SkillDefinition?>,
        searchText: String
    ) {
        self.skills = skills
        self._editingSkill = editingSkill
        self.searchText = searchText
    }

    private var filteredSkills: [SkillDefinition] {
        if searchText.isEmpty { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        if filteredSkills.isEmpty {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView(
                    "No Built-in Skills",
                    systemImage: "shield.slash",
                    description: Text("No built-in system skills were found in the runtime directory.")
                )
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
                    ForEach(filteredSkills) { skill in
                        builtinCard(for: skill)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
        }
    }

    private func builtinCard(for skill: SkillDefinition) -> some View {
        ResourceCardView(
            title: skill.name,
            subtitle: skill.path,
            summary: skill.description,
            iconName: "shield.fill",
            iconGradient: DesignTokens.Gradients.coreTools,
            badges: {
                ResourcePillBadge(title: "Built-in", color: .blue)
                ResourcePillBadge.category(skill.category)
            },
            actions: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        editingSkill = skill
                    } label: {
                        Image(systemName: "pencil.line")
                    }
                    .buttonStyle(.borderless)
                    .help("View and edit SKILL.md")

                    Button {
                        NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            editingSkill = skill
        }
        .contextMenu {
            Button {
                editingSkill = skill
            } label: {
                Label("View and Edit SKILL.md", systemImage: "pencil.line")
            }
            Button {
                NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }
        }
    }
}
