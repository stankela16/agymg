import SwiftUI

public struct SkillEditorFileTabBar: View {
    public let files: [URL]
    public let selectedFileURL: URL?
    public let onSelectFile: (URL) -> Void

    public init(
        files: [URL],
        selectedFileURL: URL?,
        onSelectFile: @escaping (URL) -> Void
    ) {
        self.files = files
        self.selectedFileURL = selectedFileURL
        self.onSelectFile = onSelectFile
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(files, id: \.path) { file in
                    let isSelected = selectedFileURL?.path == file.path
                    let isMain = file.lastPathComponent == "SKILL.md"
                    let isRef = file.path.contains("/references/")

                    Button {
                        if !isSelected {
                            onSelectFile(file)
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Image(systemName: isMain ? "doc.text.fill" : (isRef ? "text.book.closed.fill" : "applescript.fill"))
                                .font(.caption2)
                            Text(isMain ? "SKILL.md" : file.lastPathComponent)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, DesignTokens.Spacing.sm + 2)
                        .padding(.vertical, DesignTokens.Spacing.xs + 1)
                        .background(isSelected ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08))
                        .foregroundStyle(isSelected ? Color.blue : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("Switch to file: \(file.lastPathComponent)")
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .background(DesignTokens.Colors.controlBackground)
    }
}
