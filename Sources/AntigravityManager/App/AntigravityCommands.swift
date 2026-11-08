import SwiftUI
import AppKit

/// Apple HIG compliant menu bar commands structure.
/// Implements standard macOS application menu hierarchy:
/// - App Menu: About, Settings… (⌘,)
/// - File Menu: New Project… (⌘N), Open Project… (⌘O), Open Recent submenu, Sync All (⌘S), Sync Active (⌥⌘S), Reveal Vault (⇧⌘R)
/// - Edit Menu: Standard clipboard & find (TextEditingCommands)
/// - View Menu: Section navigation (⌘1-⌘5) with native system checkmarks, Sidebar toggle (⌃⌘S), Reload Data (⌘R)
/// - Window Menu: Bring All to Front, Open Control Center (⌘0)
/// - Help Menu: Documentation, Apple HIG & Bjango guides, Report Issue
public struct AntigravityCommands: Commands {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some Commands {
        // MARK: - Standard Edit Menu (Undo, Redo, Cut, Copy, Paste, Select All)
        TextEditingCommands()

        // MARK: - Standard Sidebar Commands (Show/Hide Sidebar with ⌃⌘S)
        SidebarCommands()

        // MARK: - File Menu
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                state.newProjectDialog()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Open Project…") {
                state.openProjectDialog()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Menu("Open Recent") {
                if state.projects.isEmpty {
                    Text("No Recent Workspaces")
                } else {
                    ForEach(state.projects) { project in
                        Button(project.name) {
                            state.selectedProjectId = project.id
                            state.navigationSelection = .project(project.id)
                            WindowRouter.triggerOpen()
                        }
                    }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Sync All Workspaces") {
                state.syncAll()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(state.isSyncing)

            Button("Sync Active Workspace") {
                if let project = state.selectedProject {
                    state.syncProject(project)
                } else {
                    state.syncAll()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(state.isSyncing)

            Divider()

            Button("Reveal Master Vault in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PathConstants.vaultDirectory.path)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        // MARK: - View Menu (Native Checkmark Section Navigation)
        CommandGroup(before: .sidebar) {
            Toggle("Master Vault", isOn: Binding(
                get: { state.navigationSelection == .masterVault },
                set: { if $0 { state.navigationSelection = .masterVault; WindowRouter.triggerOpen() } }
            ))
            .keyboardShortcut("1", modifiers: [.command])

            Toggle("Global Core", isOn: Binding(
                get: { state.navigationSelection == .globalCore },
                set: { if $0 { state.navigationSelection = .globalCore; WindowRouter.triggerOpen() } }
            ))
            .keyboardShortcut("2", modifiers: [.command])

            Toggle("Plugins Catalog", isOn: Binding(
                get: { state.navigationSelection == .plugins },
                set: { if $0 { state.navigationSelection = .plugins; WindowRouter.triggerOpen() } }
            ))
            .keyboardShortcut("3", modifiers: [.command])

            Toggle("System Built-ins", isOn: Binding(
                get: { state.navigationSelection == .systemBuiltins },
                set: { if $0 { state.navigationSelection = .systemBuiltins; WindowRouter.triggerOpen() } }
            ))
            .keyboardShortcut("4", modifiers: [.command])

            Toggle("Sync Engine Logs", isOn: Binding(
                get: { state.navigationSelection == .syncLogs },
                set: { if $0 { state.navigationSelection = .syncLogs; WindowRouter.triggerOpen() } }
            ))
            .keyboardShortcut("5", modifiers: [.command])

            Divider()
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Button("Reload System Data") {
                Task { await state.loadData() }
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        // MARK: - Window Menu
        CommandGroup(after: .windowArrangement) {
            Button("Antigravity Control Center") {
                WindowRouter.triggerOpen()
            }
            .keyboardShortcut("0", modifiers: [.command])
        }

        // MARK: - Help Menu
        CommandGroup(replacing: .help) {
            Button("agymg Documentation") {
                if let url = URL(string: "https://github.com/stankela16/agymg#readme") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Apple macOS Human Interface Guidelines") {
                if let url = URL(string: "https://developer.apple.com/design/human-interface-guidelines/designing-for-macos") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Bjango Menu Bar Extras Guidelines") {
                if let url = URL(string: "https://bjango.com/articles/designingmenubarextras/") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            // HIG: No ellipsis because it immediately opens an external link without prompting for inputs
            Button("Report an Issue") {
                if let url = URL(string: "https://github.com/stankela16/agymg/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
