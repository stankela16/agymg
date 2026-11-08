import SwiftUI

public struct SkillEditorSheet: View {
    public let skill: SkillDefinition
    public var onSave: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var editorState: SkillEditorState

    public init(skill: SkillDefinition, onSave: ((String) -> Void)? = nil) {
        self.skill = skill
        self.onSave = onSave
        _editorState = State(wrappedValue: SkillEditorState(skill: skill))
    }

    public var body: some View {
        @Bindable var state = editorState

        VStack(spacing: 0) {
            SkillEditorHeaderView(
                skill: skill,
                targetFileURL: state.targetFileURL,
                isReadOnly: state.isReadOnly,
                onForkToVault: {
                    _ = state.forkToVault()
                    onSave?(state.content)
                },
                onDismiss: { dismiss() }
            )

            Divider()

            if state.availableFiles.count > 1 {
                SkillEditorFileTabBar(
                    files: state.availableFiles,
                    selectedFileURL: state.targetFileURL,
                    onSelectFile: { file in
                        state.switchToFile(file, onSave: onSave)
                    }
                )
                Divider()
            }

            if state.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading file…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.errorMessage {
                ContentUnavailableView {
                    Label("Failed to Load File", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MacCodeEditorView(text: $state.content, isReadOnly: state.isReadOnly)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            SkillEditorFooterView(
                content: state.content,
                isModified: state.isModified,
                isReadOnly: state.isReadOnly,
                statusFeedback: state.statusFeedback,
                onDiscard: { state.discardChanges() },
                onClose: { dismiss() },
                onSave: { state.saveChanges(onSave: onSave) }
            )
        }
        .frame(minWidth: 780, idealWidth: 880, maxWidth: 1100,
               minHeight: 520, idealHeight: 620, maxHeight: 850)
        .background(DesignTokens.Colors.windowBackground)
        .onAppear {
            state.discoverAndLoadFiles()
        }
    }
}
