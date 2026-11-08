import SwiftUI

public struct NewSkillSheet: View {
    @Bindable var state: AppState
    public var onCreated: ((SkillDefinition) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var skillId: String = ""
    @State private var displayName: String = ""
    @State private var description: String = ""
    @State private var selectedCategory: String = "Core & Tools"
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    private let availableCategories = [
        "Core & Tools",
        "Swift & Apple",
        "Multi-Agent & Review",
        "Web & Frontend",
        "Video & Remotion",
        "System & Engine"
    ]

    public init(state: AppState, onCreated: ((SkillDefinition) -> Void)? = nil) {
        self.state = state
        self.onCreated = onCreated
    }

    private var sanitizedId: String {
        skillId.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
    }

    private var isIdAvailable: Bool {
        guard !sanitizedId.isEmpty else { return false }
        return !state.skills.contains { $0.id == sanitizedId }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    if let error = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(hex: 0xF5222D))
                            Text(error)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: 0xF5222D))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFFF1F0))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Field 1: Name & ID
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Skill Name")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.ink)
                        TextField("e.g., Code Review Swarm", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: displayName) { _, newVal in
                                if skillId.isEmpty || skillId == deriveSlug(from: newVal) {
                                    skillId = deriveSlug(from: newVal)
                                }
                            }

                        HStack(spacing: 6) {
                            Text("Folder ID:")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.inkTertiary)
                            TextField("skill-id", text: $skillId)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(4)
                                .background(DesignTokens.surfaceContainer)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 180)

                            if !sanitizedId.isEmpty {
                                if isIdAvailable {
                                    HStack(spacing: 2) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Available")
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DesignTokens.secondary)
                                } else {
                                    HStack(spacing: 2) {
                                        Image(systemName: "xmark.circle.fill")
                                        Text("Already exists")
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(hex: 0xF5222D))
                                }
                            }
                        }
                    }

                    // Field 2: Category
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.ink)
                        Picker("", selection: $selectedCategory) {
                            ForEach(availableCategories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    // Field 3: Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Skill Description (YAML frontmatter)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.ink)
                        TextField("Describe what this skill solves and when an agent should trigger it...", text: $description, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)
                    }

                    // SKILL.md Path Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location on Mac:")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.inkTertiary)
                        Text("~/.gemini/manager-vault/skills/\(sanitizedId.isEmpty ? "<id>" : sanitizedId)/SKILL.md")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkSecondary)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignTokens.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(DesignTokens.Spacing.lg)
            }

            Divider()

            // Footer
            footerBar
        }
        .frame(width: 520, height: 440)
        .background(DesignTokens.background)
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.secondary)
            Text("New Skill in Master Vault")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var footerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                createSkillAction()
            } label: {
                if isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Create Skill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primaryContainer)
            .disabled(!isIdAvailable || isCreating)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func deriveSlug(from name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func createSkillAction() {
        guard isIdAvailable else { return }
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let skill = try await state.createVaultSkill(
                    id: sanitizedId,
                    name: displayName,
                    description: description,
                    category: selectedCategory
                )
                await MainActor.run {
                    isCreating = false
                    dismiss()
                    onCreated?(skill)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
