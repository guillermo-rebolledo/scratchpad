import AppKit
import SwiftData
import SwiftUI

@MainActor
final class CaptureController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let toastPopover = NSPopover()
    private var toastDismissalTask: Task<Void, Never>?

    init(container: ModelContainer, draft: DraftStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.and.pencil",
                accessibilityDescription: String(localized: "Capture Thought")
            )
            button.toolTip = String(localized: "Capture a Thought")
            button.target = self
            button.action = #selector(toggleCapture)
            button.sendAction(on: [.leftMouseUp])
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

    @objc private func toggleCapture() {
        popover.isShown ? popover.performClose(nil) : showCapture()
    }

    func showCapture() {
        guard let button = statusItem.button else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
