import Carbon

enum GlobalShortcutError: Error, Equatable {
    case unavailable
}

@MainActor
final class GlobalShortcutManager {
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1
    private(set) var registeredShortcut: CaptureShortcut?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        installHandler()
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ shortcut: CaptureShortcut) throws {
        guard registeredShortcut != shortcut, eventHandler != nil else {
            if registeredShortcut == shortcut { return }
            throw GlobalShortcutError.unavailable
        }

        let signature = OSType(0x54484F54) // THOT
        let identifier = EventHotKeyID(signature: signature, id: nextIdentifier)
        nextIdentifier &+= 1
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.carbonFlags,
            identifier,
            GetApplicationEventTarget(),
            0,
            &candidate
        )
        guard status == noErr, let candidate else { throw GlobalShortcutError.unavailable }

        if let hotKey {
            guard UnregisterEventHotKey(hotKey) == noErr else {
                UnregisterEventHotKey(candidate)
                throw GlobalShortcutError.unavailable
            }
        }
        hotKey = candidate
        registeredShortcut = shortcut
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
