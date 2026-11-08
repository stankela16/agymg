import SwiftUI

public struct SkillEditorFooterView: View {
    public let content: String
    public let isModified: Bool
    public let isReadOnly: Bool
    public let statusFeedback: String?
    public let onDiscard: () -> Void
    public let onClose: () -> Void
    public let onSave: () -> Void

    public init(
        content: String,
        isModified: Bool,
        isReadOnly: Bool,
        statusFeedback: String?,
        onDiscard: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.content = content
        self.isModified = isModified
        self.isReadOnly = isReadOnly
        self.statusFeedback = statusFeedback
        self.onDiscard = onDiscard
        self.onClose = onClose
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            let lineCount = content.components(separatedBy: .newlines).count
            let charCount = content.count
            Text("\(lineCount) lines · \(charCount) chars")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if isModified {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Circle()
                        .fill(DesignTokens.Colors.statusSyncing)
                        .frame(width: DesignTokens.Dimensions.statusDotSize, height: DesignTokens.Dimensions.statusDotSize)
                    Text("Modified (unsaved)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.statusSyncing)
                }
                .help("File has unsaved changes")
            }

            if let feedback = statusFeedback {
                Text(feedback)
                    .font(.caption.bold())
                    .foregroundStyle(feedback.contains("Error") ? DesignTokens.Colors.statusError : DesignTokens.Colors.statusActive)
                    .transition(.opacity)
            }

            Spacer()

            if isModified && !isReadOnly {
                Button("Discard Changes") {
                    onDiscard()
                }
                .controlSize(.small)
                .help("Discard unsaved changes and restore original content")
            }

            Button("Close") {
                onClose()
            }
            .controlSize(.small)
            .help("Close skill editor (Esc)")

            if !isReadOnly {
                Button {
                    onSave()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isModified)
                .keyboardShortcut("s", modifiers: .command)
                .help("Save changes to disk (⌘S)")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.windowBackground)
    }
}
