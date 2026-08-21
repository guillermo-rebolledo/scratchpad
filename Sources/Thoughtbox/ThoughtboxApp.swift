import AppKit
import SwiftUI

@main
struct ThoughtboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appState = AppState.shared

    var body: some Scene {
        Window("Thoughtbox", id: "main") {
            MainView()
                .environment(appState.draft)
                .modelContainer(appState.container)
        }
        .defaultSize(width: 1_050, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thought") { appState.showCapture() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            ThoughtboxSettingsView(model: appState.settings)
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
