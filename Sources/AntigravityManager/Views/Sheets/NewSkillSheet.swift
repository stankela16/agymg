import SwiftUI
import AppKit

public enum SkillSheetMode: String, CaseIterable, Sendable {
    case create = "Create New"
    case folder = "Import Folder"
    case github = "Import GitHub"
}

public struct NewSkillSheet: View {
    @Bindable var state: AppState
    public var onCreated: ((SkillDefinition) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SkillSheetMode = .create
    @State private var skillId: String = ""
    @State private var displayName: String = ""
    @State private var description: String = ""
    @State private var selectedCategory: String = "Core & Tools"
    @State private var importFolderPath: String = ""
    @State private var githubURLString: String = ""
    @State private var overwriteExisting: Bool = false
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
        SkillImportService.normalizeSkillId(skillId)
    }

    private var isIdAvailable: Bool {
        guard !sanitizedId.isEmpty else { return false }
        return !state.skills.contains { $0.id == sanitizedId }
    }

    private var canSubmit: Bool {
        guard !isCreating else { return false }
        switch mode {
        case .create:
            return isIdAvailable
        case .folder:
            return !importFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .github:
            return !githubURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Picker("Mode", selection: $mode) {
                        ForEach(SkillSheetMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if let error = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DesignTokens.Colors.statusError)
                            Text(error)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.statusError)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.statusErrorBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    switch mode {
                    case .create:
                        createFieldsSection
                    case .folder:
                        importFolderSection
                    case .github:
                        importGitHubSection
                    }
                }
                .padding(DesignTokens.Spacing.lg)
            }

            Divider()

            // Footer
            footerBar
        }
        .frame(width: 520, height: 460)
        .background(DesignTokens.background)
    }

    @ViewBuilder
    private var createFieldsSection: some View {
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
                        .foregroundStyle(DesignTokens.Colors.statusError)
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

    @ViewBuilder
    private var importFolderSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Source Skill Folder (containing SKILL.md)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.ink)

            HStack(spacing: DesignTokens.Spacing.xs) {
                TextField("/path/to/skill-folder", text: $importFolderPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                Button("Browse…") {
                    chooseSkillFolder()
                }
                .buttonStyle(.bordered)
            }

            importCommonOptionsView(placeholderId: URL(fileURLWithPath: importFolderPath).lastPathComponent)
        }
    }

    @ViewBuilder
    private var importGitHubSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("GitHub Repository or Subfolder URL")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.ink)

            TextField("https://github.com/owner/repo/tree/main/skills/my-skill", text: $githubURLString)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            Text("Clones shallowly over HTTPS via system git, validates SKILL.md, and copies files cleanly into ~/.gemini/manager-vault/skills/.")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            importCommonOptionsView(placeholderId: "derived-from-url")
        }
    }

    @ViewBuilder
    private func importCommonOptionsView(placeholderId: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("Custom Vault ID (optional):")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesignTokens.inkSecondary)
                TextField(placeholderId.isEmpty ? "skill-id" : placeholderId, text: $skillId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 200)
            }

            Toggle("Overwrite if skill already exists in Master Vault", isOn: $overwriteExisting)
                .font(.system(size: 11))
                .tint(DesignTokens.primaryContainer)
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: mode == .create ? "sparkles" : "square.and.arrow.down")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.secondary)
            Text(mode == .create ? "New Skill in Master Vault" : "Import Skill into Master Vault")
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
                submitAction()
            } label: {
                if isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Text(mode == .create ? "Create Skill" : "Import Skill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primaryContainer)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func chooseSkillFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Skill Folder"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            importFolderPath = url.path
        }
    }

    private func deriveSlug(from name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func submitAction() {
        guard canSubmit else { return }
        isCreating = true
        errorMessage = nil
        let customIdValue = sanitizedId.isEmpty ? nil : sanitizedId

        Task {
            do {
                let skill: SkillDefinition
                switch mode {
                case .create:
                    skill = try await state.createVaultSkill(
                        id: sanitizedId,
                        name: displayName,
                        description: description,
                        category: selectedCategory
                    )
                case .folder:
                    let url = URL(fileURLWithPath: importFolderPath.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
                    skill = try await state.importVaultSkill(
                        fromFolder: url,
                        customId: customIdValue,
                        overwrite: overwriteExisting
                    )
                case .github:
                    skill = try await state.importVaultSkill(
                        fromGitHubURL: githubURLString,
                        customId: customIdValue,
                        overwrite: overwriteExisting
                    )
                }
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
