import SwiftUI

public struct SettingsVaultTab: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundStyle(DesignTokens.secondary)
                        Text("Workspace Projects Access")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.ink)

                        Spacer()

                        if state.isProjectsFolderAuthorized {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("Connected").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(DesignTokens.tierOrange).frame(width: 6, height: 6)
                                Text("Not Connected").font(.system(size: 11, weight: .medium)).foregroundStyle(DesignTokens.tierOrange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.tierOrange.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    Text("Authorizing your projects folder enables automatic repository discovery, per-project MCP isolation, and skill symlinking without repeated macOS permission prompts.")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Button {
                            Task {
                                await state.authorizeProjectsFolder()
                            }
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xxs) {
                                Image(systemName: "folder.badge.plus")
                                Text(state.isProjectsFolderAuthorized ? "Change Folder…" : "Connect Projects Folder…")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if state.isProjectsFolderAuthorized {
                            Button("Show Onboarding Again") {
                                state.resetProjectsFolderAuthorization()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Resets folder authorization and shows the welcome screen in Control Center")
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.xxs)
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)
            } header: {
                Text("Workspaces")
            }

            Section {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Master Vault Location:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.ink)

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(PathConstants.vaultDirectory.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PathConstants.vaultDirectory.path)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Global MCP Config:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.ink)

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(PathConstants.globalMCPConfigFile.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PathConstants.globalMCPConfigFile.path)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)
            } header: {
                Text("Disk Locations")
            }

            Section {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Button {
                            state.syncAll()
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xxs) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Force Sync (Flush Symlinks)")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.primaryContainer)
                        .controlSize(.small)
                        .help("Synchronize all global and project resources to disk (⌘S)")

                        Button {
                            Task { await state.loadData() }
                        } label: {
                            Text("Reload Definitions")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Rescan all MCP servers, skills, and plugins from disk")
                    }

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Button {
                            Task { await state.createManualConfigBackup() }
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xxs) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Create Config Backup")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Save a timestamped snapshot of your Antigravity & Claude Code config files")

                        Button("Reveal Backups in Finder") {
                            try? FileManager.default.createDirectory(at: PathConstants.vaultBackupsDirectory, withIntermediateDirectories: true)
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PathConstants.vaultBackupsDirectory.path)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open ~/.gemini/manager-vault/backups in Finder")
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)
            } header: {
                Text("Maintenance & Recovery")
            }
        }
        .formStyle(.grouped)
    }
}
