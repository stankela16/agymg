import SwiftUI

public struct SlashCommandsTab: View {
    public let commands: [SlashCommandDefinition]
    public var searchText: String

    @State private var selectedCommand: SlashCommandDefinition? = nil

    public init(commands: [SlashCommandDefinition], searchText: String) {
        self.commands = commands
        self.searchText = searchText
    }

    private var filteredCommands: [SlashCommandDefinition] {
        if searchText.isEmpty { return commands }
        return commands.filter {
            $0.command.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        Group {
            if filteredCommands.isEmpty {
                if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView(
                        "No Slash Commands",
                        systemImage: "terminal",
                        description: Text("No slash commands found in the Antigravity configuration.")
                    )
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
                        ForEach(filteredCommands) { cmd in
                            commandCard(for: cmd)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
            }
        }
        .sheet(item: $selectedCommand) { cmd in
            commandDetailSheet(for: cmd)
        }
    }

    private func commandCard(for cmd: SlashCommandDefinition) -> some View {
        ResourceCardView(
            title: cmd.name,
            subtitle: "Antigravity Chat Command",
            summary: cmd.description,
            iconName: "terminal.fill",
            iconGradient: DesignTokens.Gradients.videoRemotion,
            badges: {
                ResourcePillBadge.category(cmd.category)
            },
            actions: {
                Text(cmd.command)
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundStyle(.purple)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
                    .help("Slash command: \(cmd.command)")
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCommand = cmd
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd.command, forType: .string)
            } label: {
                Label("Copy Command (\(cmd.command))", systemImage: "doc.on.doc")
            }
            Button {
                selectedCommand = cmd
            } label: {
                Label("Show Details", systemImage: "info.circle")
            }
        }
    }

    private func commandDetailSheet(for cmd: SlashCommandDefinition) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: DesignTokens.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(cmd.name)
                        .font(.title3.bold())
                        .foregroundStyle(DesignTokens.ink)
                    HStack(spacing: 8) {
                        Text(cmd.command)
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())

                        ResourcePillBadge.category(cmd.category)
                    }
                }

                Spacer()

                Button {
                    selectedCommand = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Quick Run Box
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW TO USE IN ANTIGRAVITY CHAT")
                            .font(.caption.bold())
                            .foregroundStyle(DesignTokens.inkTertiary)

                        HStack {
                            Text(cmd.command)
                                .font(.system(.body, design: .monospaced).bold())
                                .foregroundStyle(.purple)
                            Text("+ your prompt or task")
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.inkSecondary)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd.command, forType: .string)
                            } label: {
                                Label("Copy Command", systemImage: "doc.on.doc")
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(DesignTokens.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Purpose
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PURPOSE & SUMMARY")
                            .font(.caption.bold())
                            .foregroundStyle(DesignTokens.inkTertiary)

                        Text(cmd.description)
                            .font(.system(size: 13.5))
                            .foregroundStyle(DesignTokens.ink)
                            .lineSpacing(3)
                    }

                    // Full Protocol
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SYSTEM PROTOCOL & ENGINE RULES")
                                .font(.caption.bold())
                                .foregroundStyle(DesignTokens.inkTertiary)
                            Spacer()
                            Text("Runtime Directive")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(cmd.fullProtocol)
                                .font(.system(size: 12.5, design: .default))
                                .foregroundStyle(DesignTokens.inkSecondary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.surfaceContainerLowest)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(DesignTokens.divider, lineWidth: 1)
                        )
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    selectedCommand = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(DesignTokens.surfaceContainerLow)
        }
        .frame(minWidth: 620, idealWidth: 680, maxWidth: 760, minHeight: 480, idealHeight: 560, maxHeight: 680)
        .background(DesignTokens.Colors.windowBackground)
    }
}
