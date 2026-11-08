import SwiftUI
import AppKit

public struct SkillEditorHeaderView: View {
    public let skill: SkillDefinition
    public let targetFileURL: URL?
    public let isReadOnly: Bool
    public var onForkToVault: (() -> Void)? = nil
    public let onDismiss: () -> Void

    public init(
        skill: SkillDefinition,
        targetFileURL: URL?,
        isReadOnly: Bool,
        onForkToVault: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.skill = skill
        self.targetFileURL = targetFileURL
        self.isReadOnly = isReadOnly
        self.onForkToVault = onForkToVault
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            Image(systemName: isReadOnly ? "lock.shield.fill" : "doc.text.fill")
                .font(.title2)
                .foregroundStyle(isReadOnly ? DesignTokens.Colors.statusSyncing : DesignTokens.Colors.statusProject)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(skill.name)
                        .font(.headline)
                        .foregroundStyle(DesignTokens.ink)

                    originBadge

                    Text(skill.category)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.surfaceContainer)
                        .clipShape(Capsule())

                    if isReadOnly {
                        Text("Read-Only")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.Colors.statusSyncingBg)
                            .foregroundStyle(DesignTokens.Colors.statusSyncing)
                            .clipShape(Capsule())
                    }
                }

                if let fileURL = targetFileURL {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(fileURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fileURL.path, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy file path to clipboard")
                    }
                }
            }

            Spacer()

            if skill.origin == .builtin, let onForkToVault {
                Button {
                    onForkToVault()
                } label: {
                    Label("Fork to Vault", systemImage: "arrow.triangle.branch")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.purple)
                .help("Copy this skill into your Master Vault for permanent customization")
            }

            if let fileURL = targetFileURL {
                Button {
                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Finder", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.small)
                .help("Reveal file in Finder")

                Button {
                    NSWorkspace.shared.open(fileURL)
                } label: {
                    Label("External Editor", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
                .help("Open in default code editor")
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close editor (Esc)")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.windowBackground)
    }

    private var originBadge: some View {
        let (title, color) = originMetadata
        return Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var originMetadata: (String, Color) {
        switch skill.origin {
        case .projectLocal: ("Local Project", .blue)
        case .vault: ("Master Vault", .purple)
        case .global: ("Global Core", .green)
        case .builtin: ("Built-in", .orange)
        }
    }
}
