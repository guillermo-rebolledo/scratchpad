import AppKit
import SwiftData
import SwiftUI

@MainActor
final class CaptureController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

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
}

extension Notification.Name {
    static let focusCaptureEditor = Notification.Name("Thoughtbox.focusCaptureEditor")
}
