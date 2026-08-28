import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI

@MainActor
final class CaptureController: NSObject, NSPopoverDelegate {
    let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let toastPopover = NSPopover()
    private var toastDismissalTask: Task<Void, Never>?
    private var captureSelection: (() -> Void)?
    private var openThought: (() -> Void)?
    private var openLibrary: (() -> Void)?
    private var openSettings: (() -> Void)?
    private var checkForUpdates: (() -> Void)?
    private var shortcutItems: [GlobalShortcutKind: NSMenuItem] = [:]

    init(container: ModelContainer, draft: DraftStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.and.pencil",
                accessibilityDescription: String(localized: "Thoughtbox")
            )
            button.image?.isTemplate = true
            button.toolTip = String(localized: "Thoughtbox")
            button.identifier = NSUserInterfaceItemIdentifier("thoughtbox.statusItem")
            button.setAccessibilityIdentifier("thoughtbox.statusItem")
        }

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: 420, height: 380)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: CaptureView { [weak popover] in
                popover?.performClose(nil)
            }
            .environment(draft)
            .modelContainer(container)
        )

        toastPopover.behavior = .transient
        toastPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func configureStatusMenu(
        quickCaptureShortcut: CaptureShortcut,
        selectionShortcut: CaptureShortcut,
        openThoughtShortcut: CaptureShortcut,
        captureSelection: @escaping () -> Void,
        openThought: @escaping () -> Void,
        openLibrary: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.captureSelection = captureSelection
        self.openThought = openThought
        self.openLibrary = openLibrary
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates

        let menu = NSMenu()
        let quickCapture = menuItem(
            title: String(localized: "New Thought"),
            action: #selector(openCaptureFromMenu),
            shortcut: quickCaptureShortcut
        )
        let selection = menuItem(
            title: String(localized: "Capture Selection"),
            action: #selector(captureSelectionFromMenu),
            shortcut: selectionShortcut
        )
        let thought = menuItem(
            title: String(localized: "Open Thought"),
            action: #selector(openThoughtFromMenu),
            shortcut: openThoughtShortcut
        )
        shortcutItems = [
            .quickCapture: quickCapture,
            .captureSelection: selection,
            .menuBarThought: thought
        ]
        menu.items = [
            quickCapture,
            selection,
            thought,
            .separator(),
            menuItem(
                title: String(localized: "Open Thoughtbox"),
                action: #selector(openLibraryFromMenu),
                shortcut: CaptureShortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: [.command])
            ),
            menuItem(
                title: String(localized: "Settings…"),
                action: #selector(openSettingsFromMenu),
                shortcut: CaptureShortcut(keyCode: UInt32(kVK_ANSI_Comma), modifiers: [.command])
            ),
            menuItem(
                title: String(localized: "Check for Updates…"),
                action: #selector(checkForUpdatesFromMenu),
                shortcut: CaptureShortcut(keyCode: UInt32(kVK_ANSI_U), modifiers: [.command, .shift])
            ),
            .separator(),
            menuItem(
                title: String(localized: "Quit Thoughtbox"),
                action: #selector(quitFromMenu),
                shortcut: CaptureShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: [.command])
            )
        ]
        statusItem.menu = menu
    }

    func updateStatusMenuShortcut(_ shortcut: CaptureShortcut, for kind: GlobalShortcutKind) {
        guard let item = shortcutItems[kind] else { return }
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
    }

    private func menuItem(title: String, action: Selector, shortcut: CaptureShortcut) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut.menuKeyEquivalent)
        item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
        item.target = self
        return item
    }

    @objc private func openCaptureFromMenu() {
        afterStatusMenuCloses { [weak self] in self?.showCapture() }
    }

    @objc private func captureSelectionFromMenu() {
        afterStatusMenuCloses { [weak self] in self?.captureSelection?() }
    }

    @objc private func openThoughtFromMenu() {
        afterStatusMenuCloses { [weak self] in self?.openThought?() }
    }

    @objc private func openLibraryFromMenu() {
        openLibrary?()
    }

    @objc private func openSettingsFromMenu() {
        openSettings?()
    }

    @objc private func checkForUpdatesFromMenu() {
        checkForUpdates?()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func afterStatusMenuCloses(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async(execute: action)
    }

    func showCapture() {
        guard let button = statusItem.button else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .focusCaptureEditor, object: nil)
    }

    func showCaptureWithSelection() {
        showCapture()
        NotificationCenter.default.post(name: .moveCaptureEditorToEnd, object: nil)
        announceForAccessibility(
            String(localized: "selectionCapture.added", defaultValue: "Selected text added to the Draft."),
            priority: .high
        )
    }

    func presentSelectionFailure(
        _ presentation: SelectionFailurePresentation,
        openAccessibilitySettings: @escaping @MainActor () -> Void
    ) {
        announceForAccessibility(presentation.message, priority: .high)
        switch presentation.style {
        case .alert:
            showPermissionAlert(presentation, openAccessibilitySettings: openAccessibilitySettings)
        case .toast:
            showToast(presentation, openAccessibilitySettings: openAccessibilitySettings)
        }
    }

    private func showPermissionAlert(
        _ presentation: SelectionFailurePresentation,
        openAccessibilitySettings: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "selectionCapture.permissionTitle", defaultValue: "Allow Selection Capture")
        alert.informativeText = presentation.message
        alert.addButton(withTitle: String(localized: "selectionCapture.openSettings", defaultValue: "Open Accessibility Settings"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }
    }

    private func showToast(
        _ presentation: SelectionFailurePresentation,
        openAccessibilitySettings: @escaping @MainActor () -> Void
    ) {
        guard let button = statusItem.button else { return }
        toastDismissalTask?.cancel()
        toastPopover.performClose(nil)
        toastPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        toastPopover.contentSize = NSSize(width: 340, height: presentation.offersAccessibilitySettings ? 112 : 82)
        toastPopover.contentViewController = NSHostingController(
            rootView: SelectionCaptureToast(
                message: presentation.message,
                offersAccessibilitySettings: presentation.offersAccessibilitySettings,
                openAccessibilitySettings: openAccessibilitySettings
            )
        )
        toastPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        toastDismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.toastPopover.performClose(nil)
        }
    }
}

extension Notification.Name {
    static let focusCaptureEditor = Notification.Name("Thoughtbox.focusCaptureEditor")
    static let moveCaptureEditorToEnd = Notification.Name("Thoughtbox.moveCaptureEditorToEnd")
}

private struct SelectionCaptureToast: View {
    let message: String
    let offersAccessibilitySettings: Bool
    let openAccessibilitySettings: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AccessibleErrorMessage(
                message: message,
                accessibilityLabel: "Capture Selection error: \(message)",
                identifier: "selectionCapture.toast"
            )
            if offersAccessibilitySettings {
                Button("Open Accessibility Settings", action: openAccessibilitySettings)
                    .accessibilityHint("Opens Privacy and Security settings for Thoughtbox.")
                    .accessibilityIdentifier("selectionCapture.toast.openSettings")
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}
