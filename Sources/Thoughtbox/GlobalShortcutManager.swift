import Carbon

enum GlobalShortcutError: Error, Equatable {
    case unavailable
}

enum GlobalShortcutKind: UInt32, CaseIterable, Sendable {
    case quickCapture = 1
    case captureSelection = 2
    case menuBarThought = 3
}

@MainActor
final class GlobalShortcutManager {
    private static let signature = OSType(0x54484F54) // THOT

    nonisolated(unsafe) private var hotKeys: [GlobalShortcutKind: EventHotKeyRef] = [:]
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private var registeredShortcuts: [GlobalShortcutKind: CaptureShortcut] = [:]
    private let actions: [GlobalShortcutKind: () -> Void]

    var registeredShortcut: CaptureShortcut? { registeredShortcuts[.quickCapture] }

    init(action: @escaping () -> Void) {
        actions = [.quickCapture: action]
        installHandler()
    }

    init(
        quickCapture: @escaping () -> Void,
        captureSelection: @escaping () -> Void,
        menuBarThought: @escaping () -> Void = {}
    ) {
        actions = [
            .quickCapture: quickCapture,
            .captureSelection: captureSelection,
            .menuBarThought: menuBarThought
        ]
        installHandler()
    }

    deinit {
        for hotKey in hotKeys.values { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ shortcut: CaptureShortcut) throws {
        try register(shortcut, for: .quickCapture)
    }

    func register(_ shortcut: CaptureShortcut, for kind: GlobalShortcutKind) throws {
        guard registeredShortcuts[kind] != shortcut, eventHandler != nil else {
            if registeredShortcuts[kind] == shortcut { return }
            throw GlobalShortcutError.unavailable
        }

        let identifier = EventHotKeyID(signature: Self.signature, id: kind.rawValue)
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

        if let current = hotKeys[kind] {
            guard UnregisterEventHotKey(current) == noErr else {
                UnregisterEventHotKey(candidate)
                throw GlobalShortcutError.unavailable
            }
        }
        hotKeys[kind] = candidate
        registeredShortcuts[kind] = shortcut
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      identifier.signature == GlobalShortcutManager.signature,
                      let kind = GlobalShortcutKind(rawValue: identifier.id) else {
                    return noErr
                }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in manager.actions[kind]?() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
    }
}
