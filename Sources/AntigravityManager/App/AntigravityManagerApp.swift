import SwiftUI
import AppKit
import Darwin

@main
enum MainEntry {
    static func main() {
        let args = CommandLine.arguments
        if CLIRunner.shouldHandle(arguments: args) {
            let code = CLIRunner.runFromCommandLine(arguments: args)
            Darwin.exit(code)
        }
        AntigravityManagerApp.main()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.activate(ignoringOtherApps: true)
        WindowRouter.triggerOpen()
        return true
    }
}

struct AntigravityManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        HotKeyManager.shared.register()
    }

    var body: some Scene {
        Window("agymg", id: "control-center") {
            ControlCenterView(state: appState)
                .task {
                    setupWindowRouter()
                }
                .onAppear {
                    setupWindowRouter()
                }
        }
        .commands {
            AntigravityCommands(state: appState)
        }

        MenuBarExtra {
            MenuBarPopoverView(state: appState)
                .task {
                    setupWindowRouter()
                }
                .onAppear {
                    setupWindowRouter()
                }
        } label: {
            if let icon = MenuBarIconProvider.icon(hasRecommendations: appState.hasActiveProjectRecommendations) {
                Image(nsImage: icon)
            } else {
                Image(systemName: "bolt.shield")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: appState)
        }
    }

    private func setupWindowRouter() {
        WindowRouter.openControlCenter = {
            openWindow(id: "control-center")
        }
    }
}
