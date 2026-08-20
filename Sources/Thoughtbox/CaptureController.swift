import AppKit
import Carbon
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
                accessibilityDescription: "Capture Thought"
            )
            button.toolTip = "Capture a Thought"
            button.target = self
            button.action = #selector(toggleCapture)
            button.sendAction(on: [.leftMouseUp])
        }

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: 420, height: 330)
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
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NotificationCenter.default.post(name: .focusCaptureEditor, object: nil)
    }
}

@MainActor
final class GlobalShortcutManager {
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        installHandler()

        let signature = OSType(0x54484F54) // THOT
        let identifier = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in manager.action() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
    }
}

extension Notification.Name {
    static let focusCaptureEditor = Notification.Name("Thoughtbox.focusCaptureEditor")
}
