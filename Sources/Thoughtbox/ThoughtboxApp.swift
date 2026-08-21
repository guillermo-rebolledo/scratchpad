import AppKit
import Sparkle
import SwiftUI

enum ThoughtboxWindowMetrics {
    /// The smallest content size supported by the Library's adaptive three-column layout.
    static let minimumWidth: CGFloat = 840
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
            ThoughtCommands()
            SidebarCommands()
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

private struct ThoughtCommands: Commands {
    @FocusedValue(\.thoughtCommandActions) private var actions
    @FocusedValue(\.thoughtSelectionCommandActions) private var selectionActions

    var body: some Commands {
        CommandMenu("Thought") {
            Button(actions?.isEditing == true ? "Done Editing" : "Edit Thought") {
                actions?.toggleEditing()
            }
            .keyboardShortcut("e", modifiers: [.command, .control])
            .help(actions?.isEditing == true
                ? "Saves pending changes and returns to rendered Markdown."
                : "Shows the canonical Markdown source for editing.")
            .disabled(actions == nil)

            Divider()

            if selectionActions?.isTrash == true {
                Button("Restore Selected", systemImage: "arrow.uturn.backward") {
                    selectionActions?.restore()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Restores selected Thoughts to their former destinations when available.")
                .disabled((selectionActions?.selectionCount ?? 0) == 0)

                Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) {
                    selectionActions?.deletePermanently()
                }
                .help("Asks for confirmation before permanently deleting the selected Thoughts.")
                .disabled((selectionActions?.selectionCount ?? 0) == 0)

                Button("Export Selected Trash…", systemImage: "square.and.arrow.up") {
                    selectionActions?.exportTrash()
                }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .help("Exports the selected trashed Thoughts as portable Markdown.")
                .disabled((selectionActions?.selectionCount ?? 0) == 0)
            } else {
                Menu((selectionActions?.selectionCount ?? 0) > 1 ? "Move Selected Thoughts To" : "Move Thought To") {
                    ForEach(selectionActions?.destinations ?? []) { destination in
                        Button {
                            selectionActions?.move(destination.destination)
                        } label: {
                            if destination.isCurrent {
                                Label(destination.name, systemImage: "checkmark")
                            } else {
                                Text(destination.name)
                            }
                        }
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help("Moves the selected active Thoughts to Inbox or one Project.")
                .disabled((selectionActions?.selectionCount ?? 0) == 0)

                Button(
                    (selectionActions?.selectionCount ?? 0) > 1 ? "Move Selected to Trash" : "Move to Trash",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    selectionActions?.trash()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Moves the selected active Thoughts to Trash. You can restore them later.")
                .disabled((selectionActions?.selectionCount ?? 0) == 0)
            }
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
