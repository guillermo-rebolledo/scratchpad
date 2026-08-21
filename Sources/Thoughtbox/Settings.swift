import AppKit
import Carbon
import Foundation
import ServiceManagement
import SwiftUI

struct ShortcutModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    let rawValue: UInt8

    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let shift = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.command) { value.insert(.command) }
        self = value
    }

    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        if contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

struct CaptureShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: ShortcutModifiers

    static let `default` = CaptureShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: [.control, .option]
    )

    var isValid: Bool {
        !modifiers.intersection([.control, .option, .command]).isEmpty
    }

    var displayName: String {
        displayName(resolvedKeyName: KeyboardLayoutKeyNameResolver.name(for: keyCode))
    }

    func displayName(resolvedKeyName: String?) -> String {
        let modifierNames = [
            (ShortcutModifiers.control, String(localized: "shortcut.modifier.control", defaultValue: "Control")),
            (.option, String(localized: "shortcut.modifier.option", defaultValue: "Option")),
            (.shift, String(localized: "shortcut.modifier.shift", defaultValue: "Shift")),
            (.command, String(localized: "shortcut.modifier.command", defaultValue: "Command"))
        ].compactMap { modifiers.contains($0.0) ? $0.1 : nil }
        return (modifierNames + [Self.keyName(keyCode, resolvedKeyName: resolvedKeyName)]).joined(separator: "–")
    }

    private static func keyName(_ keyCode: UInt32, resolvedKeyName: String?) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Space): String(localized: "shortcut.key.space", defaultValue: "Space"),
            UInt32(kVK_Return): String(localized: "shortcut.key.return", defaultValue: "Return"),
            UInt32(kVK_Tab): String(localized: "shortcut.key.tab", defaultValue: "Tab"),
            UInt32(kVK_Escape): String(localized: "shortcut.key.escape", defaultValue: "Escape"),
            UInt32(kVK_Delete): String(localized: "shortcut.key.delete", defaultValue: "Delete"),
            UInt32(kVK_ForwardDelete): String(localized: "shortcut.key.forwardDelete", defaultValue: "Forward Delete"),
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓"
        ]
        if let name = names[keyCode] { return name }
        if let resolvedKeyName, !resolvedKeyName.isEmpty { return resolvedKeyName.uppercased() }
        return String(localized: "shortcut.key.unknown", defaultValue: "Key \(keyCode)")
    }
}

enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable

    var isRequested: Bool { self == .enabled || self == .requiresApproval }
}

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class SystemLoginItemService: LoginItemServicing {
    private let service = SMAppService.mainApp

    var status: LoginItemStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status == .notRegistered || status == .unavailable else { return }
            try service.register()
        } else {
            guard status.isRequested else { return }
            try service.unregister()
        }
    }
}

@MainActor
final class UITestLoginItemService: LoginItemServicing {
    private let defaults: UserDefaults
    private let shouldFail: Bool
    private let key = "settings.uiTest.launchAtLogin"

    init(defaults: UserDefaults, shouldFail: Bool) {
        self.defaults = defaults
        self.shouldFail = shouldFail
    }

    var status: LoginItemStatus { defaults.bool(forKey: key) ? .enabled : .notRegistered }

    func setEnabled(_ enabled: Bool) throws {
        if shouldFail { throw UITestLoginItemFailure() }
        defaults.set(enabled, forKey: key)
    }
}

private struct UITestLoginItemFailure: Error {}

@MainActor
@Observable
final class SettingsModel {
    private enum Key {
        static let shortcutKeyCode = "settings.shortcut.keyCode"
        static let shortcutModifiers = "settings.shortcut.modifiers"
    }

    private let defaults: UserDefaults
    private let loginItemService: LoginItemServicing
    private var registerShortcut: ((CaptureShortcut) throws -> Void)?

    private(set) var shortcut: CaptureShortcut
    private(set) var shortcutError: String?
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginNeedsApproval = false
    private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults, loginItemService: LoginItemServicing) {
        self.defaults = defaults
        self.loginItemService = loginItemService
        if let savedKeyCode = UInt32(exactly: defaults.integer(forKey: Key.shortcutKeyCode)),
           let savedModifiers = UInt8(exactly: defaults.integer(forKey: Key.shortcutModifiers)),
           defaults.object(forKey: Key.shortcutKeyCode) != nil,
           defaults.object(forKey: Key.shortcutModifiers) != nil {
            let saved = CaptureShortcut(
                keyCode: savedKeyCode,
                modifiers: ShortcutModifiers(rawValue: savedModifiers)
            )
            shortcut = saved.isValid ? saved : .default
        } else {
            shortcut = .default
        }
        refreshLaunchAtLogin()
    }

    func connectShortcutRegistration(_ registration: @escaping (CaptureShortcut) throws -> Void) {
        registerShortcut = registration
        do {
            try registration(shortcut)
            shortcutError = nil
        } catch {
            shortcutError = String(
                localized: "settings.shortcut.startupError",
                defaultValue: "The saved shortcut is unavailable. Choose another shortcut."
            )
        }
    }

    func assignShortcut(_ candidate: CaptureShortcut) {
        guard candidate.isValid else {
            shortcutError = String(
                localized: "settings.shortcut.modifierError",
                defaultValue: "Include Control, Option, or Command with the shortcut key."
            )
            return
        }
        guard let registerShortcut else { return }
        do {
            try registerShortcut(candidate)
            shortcut = candidate
            defaults.set(Int(candidate.keyCode), forKey: Key.shortcutKeyCode)
            defaults.set(Int(candidate.modifiers.rawValue), forKey: Key.shortcutModifiers)
            shortcutError = nil
        } catch {
            shortcutError = String(
                localized: "settings.shortcut.conflictError",
                defaultValue: "That shortcut is unavailable or used by another app. The previous shortcut is still active."
            )
        }
    }

    func restoreDefaultShortcut() {
        assignShortcut(.default)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        var operationError: String?
        do {
            try loginItemService.setEnabled(enabled)
        } catch {
            operationError = String(
                localized: "settings.login.failure",
                defaultValue: "Thoughtbox could not update Launch at Login. The system setting was not changed."
            )
        }
        reconcileLaunchAtLogin(operationError: operationError)
    }

    func refreshLaunchAtLogin() {
        reconcileLaunchAtLogin(operationError: nil)
    }

    private func reconcileLaunchAtLogin(operationError: String?) {
        let status = loginItemService.status
        launchAtLoginEnabled = status.isRequested
        launchAtLoginNeedsApproval = status == .requiresApproval
        if let operationError {
            launchAtLoginError = operationError
        } else if status == .unavailable {
            launchAtLoginError = String(
                localized: "settings.login.unavailable",
                defaultValue: "Launch at Login is unavailable for this copy of Thoughtbox."
            )
        } else {
            launchAtLoginError = nil
        }
    }
}

struct ThoughtboxSettingsView: View {
    @Bindable var model: SettingsModel
    @AccessibilityFocusState private var shortcutErrorFocused: Bool
    @AccessibilityFocusState private var loginErrorFocused: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "settings.shortcut.label", defaultValue: "Capture Shortcut")) {
                    ShortcutRecorderView(shortcut: model.shortcut) { shortcut in
                        model.assignShortcut(shortcut)
                    }
                        .frame(width: 210, height: 28)
                }
                Button(
                    String(localized: "settings.shortcut.restore", defaultValue: "Restore Default"),
                    action: { model.restoreDefaultShortcut() }
                )
                .disabled(model.shortcut == .default)
                .help(String(localized: "settings.shortcut.restoreHelp", defaultValue: "Reinstates Control–Option–Space."))
                .accessibilityHint(String(localized: "settings.shortcut.restoreHelp", defaultValue: "Reinstates Control–Option–Space."))
                .accessibilityIdentifier("settings.shortcut.restore")

                if let shortcutError = model.shortcutError {
                    SettingsErrorLabel(message: shortcutError, identifier: "settings.shortcut.error")
                        .accessibilityFocused($shortcutErrorFocused)
                }
            } header: {
                Text(String(localized: "settings.shortcut.section", defaultValue: "Quick Capture"))
            } footer: {
                Text(String(localized: "settings.shortcut.help", defaultValue: "Activate the recorder, then type a shortcut. The change takes effect immediately."))
            }

            Section {
                Toggle(
                    String(localized: "settings.login.label", defaultValue: "Launch at Login"),
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { enabled in model.setLaunchAtLogin(enabled) }
                    )
                )
                .help(String(localized: "settings.login.help", defaultValue: "Ask macOS to open Thoughtbox when you log in."))
                .accessibilityHint(String(localized: "settings.login.help", defaultValue: "Ask macOS to open Thoughtbox when you log in."))
                .accessibilityIdentifier("settings.login.toggle")

                if model.launchAtLoginNeedsApproval {
                    Text(String(localized: "settings.login.approval", defaultValue: "Approval is required in System Settings → General → Login Items."))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.login.approval")
                }
                if let launchAtLoginError = model.launchAtLoginError {
                    SettingsErrorLabel(message: launchAtLoginError, identifier: "settings.login.error")
                        .accessibilityFocused($loginErrorFocused)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 480, height: 310)
        .onAppear { model.refreshLaunchAtLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLaunchAtLogin()
        }
        .onChange(of: model.shortcutError) { _, error in shortcutErrorFocused = error != nil }
        .onChange(of: model.launchAtLoginError) { _, error in loginErrorFocused = error != nil }
    }
}

private struct SettingsErrorLabel: View {
    let message: String
    let identifier: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .accessibilityLabel(message)
            .accessibilityIdentifier(identifier)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: CaptureShortcut
    let onChange: (CaptureShortcut) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(shortcut: shortcut, onChange: context.coordinator.onChange)
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.onChange = onChange
        button.onChange = context.coordinator.onChange
        button.update(shortcut: shortcut)
    }

    final class Coordinator {
        var onChange: (CaptureShortcut) -> Void
        init(onChange: @escaping (CaptureShortcut) -> Void) { self.onChange = onChange }
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onChange: (CaptureShortcut) -> Void
    private var shortcut: CaptureShortcut
    private var isRecording = false

    init(shortcut: CaptureShortcut, onChange: @escaping (CaptureShortcut) -> Void) {
        self.shortcut = shortcut
        self.onChange = onChange
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        identifier = NSUserInterfaceItemIdentifier("settings.shortcut.recorder")
        setAccessibilityIdentifier("settings.shortcut.recorder")
        setAccessibilityLabel(String(localized: "settings.shortcut.recorderLabel", defaultValue: "Capture shortcut recorder"))
        setAccessibilityHelp(String(localized: "settings.shortcut.recorderHelp", defaultValue: "Activate, then type the new shortcut. Press Escape to cancel."))
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.initialFirstResponder == nil else { return }
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
    }

    @objc private func beginRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        updateAppearance()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    func update(shortcut: CaptureShortcut) {
        self.shortcut = shortcut
        if !isRecording { updateAppearance() }
    }

    private func capture(_ event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            isRecording = false
            updateAppearance()
            return
        }
        let candidate = CaptureShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
        isRecording = false
        onChange(candidate)
        updateAppearance()
    }

    private func updateAppearance() {
        if isRecording {
            title = String(localized: "settings.shortcut.recording", defaultValue: "Type a new shortcut…")
            setAccessibilityValue(title)
        } else {
            title = shortcut.displayName
            setAccessibilityValue(shortcut.displayName)
        }
    }
}
