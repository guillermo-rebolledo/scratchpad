import AppKit
import Sparkle
import SwiftUI

enum ThoughtboxWindowMetrics {
    /// The smallest content size where all three Library columns remain independently operable.
    static let minimumWidth: CGFloat = 1_050
    static let minimumHeight: CGFloat = 540
}

@main
struct ThoughtboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appState = AppState.shared

    var body: some Scene {
        Window("Thoughtbox", id: "main") {
            MainView()
                .frame(
                    minWidth: ThoughtboxWindowMetrics.minimumWidth,
                    minHeight: ThoughtboxWindowMetrics.minimumHeight
                )
                .environment(appState.draft)
                .modelContainer(appState.container)
        }
        .defaultSize(width: 1_050, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thought") { appState.showCapture() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appState.updaterController.checkForUpdates(nil)
                }
                    .help("Checks the signed Thoughtbox update channel for a newer version.")
            }
            ProjectCommands()
        }

        Settings {
            ThoughtboxSettingsView(model: appState.settings)
        }
    }
}

private struct ProjectCommands: Commands {
    @FocusedValue(\.projectCommandActions) private var actions

    var body: some Commands {
        CommandMenu("Project") {
            Button("New Project") { actions?.create() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Creates a Project in the main window.")
                .disabled(actions == nil)

            Divider()

            Button("Rename Project") { actions?.rename() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .help("Renames the selected Project without changing its order.")
                .disabled(actions?.canModifySelectedProject != true)

            Button("Delete Project") { actions?.delete() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .help("Deletes the selected Project only when it contains no active Thoughts.")
                .disabled(actions?.canModifySelectedProject != true)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.startCaptureServices()
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
