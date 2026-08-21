import AppKit
import Sparkle
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
        installUpdateMenuItem()
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

    private func installUpdateMenuItem() {
        guard let applicationMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        let selector = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        guard !applicationMenu.items.contains(where: { $0.action == selector }) else { return }
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: selector,
            keyEquivalent: ""
        )
        item.target = AppState.shared.updaterController
        item.toolTip = "Checks the signed Thoughtbox update channel for a newer version."
        applicationMenu.insertItem(item, at: min(1, applicationMenu.items.count))
    }
}
