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

    static let selectionDefault = CaptureShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: [.control, .option, .shift]
    )

    var isValid: Bool {
        UInt16(exactly: keyCode) != nil
            && !modifiers.intersection([.control, .option, .command]).isEmpty
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
        static let selectionShortcutKeyCode = "settings.selectionShortcut.keyCode"
        static let selectionShortcutModifiers = "settings.selectionShortcut.modifiers"
    }

    private let defaults: UserDefaults
    private let loginItemService: LoginItemServicing
    private var registerShortcut: ((CaptureShortcut) throws -> Void)?
    private var registerSelectionShortcut: ((CaptureShortcut) throws -> Void)?
    private var selectionPermissionStatus: ((Bool) async -> Bool)?
    private var selectionPermissionOnboardingTask: Task<Void, Never>?
    private var selectionPermissionOnboardingPending = false

    private(set) var shortcut: CaptureShortcut
    private(set) var shortcutError: String?
    private(set) var selectionShortcut: CaptureShortcut
    private(set) var selectionShortcutError: String?
    private(set) var selectionPermissionGranted: Bool?
    private(set) var selectionPermissionAlertRequested = false
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginNeedsApproval = false
    private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults, loginItemService: LoginItemServicing) {
        self.defaults = defaults
        self.loginItemService = loginItemService
        shortcut = Self.savedShortcut(
            defaults: defaults,
            keyCodeKey: Key.shortcutKeyCode,
            modifiersKey: Key.shortcutModifiers,
            fallback: .default
        )
        selectionShortcut = Self.savedShortcut(
            defaults: defaults,
            keyCodeKey: Key.selectionShortcutKeyCode,
            modifiersKey: Key.selectionShortcutModifiers,
            fallback: .selectionDefault
        )
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

    func connectSelectionShortcutRegistration(_ registration: @escaping (CaptureShortcut) throws -> Void) {
        registerSelectionShortcut = registration
        do {
            try registration(selectionShortcut)
            selectionShortcutError = nil
        } catch {
            selectionShortcutError = String(
                localized: "settings.selectionShortcut.startupError",
                defaultValue: "The saved Capture Selection shortcut is unavailable. Choose another shortcut."
            )
        }
    }

    func assignSelectionShortcut(_ candidate: CaptureShortcut) {
        guard candidate.isValid else {
            selectionShortcutError = String(
                localized: "settings.selectionShortcut.modifierError",
                defaultValue: "Include Control, Option, or Command with the shortcut key."
            )
            return
        }
        guard let registerSelectionShortcut else { return }
        do {
            try registerSelectionShortcut(candidate)
            selectionShortcut = candidate
            defaults.set(Int(candidate.keyCode), forKey: Key.selectionShortcutKeyCode)
            defaults.set(Int(candidate.modifiers.rawValue), forKey: Key.selectionShortcutModifiers)
            selectionShortcutError = nil
            requestSelectionPermissionOnboardingIfNeeded()
        } catch {
            selectionShortcutError = String(
                localized: "settings.selectionShortcut.conflictError",
                defaultValue: "That shortcut is unavailable or used by another app. The previous shortcut is still active."
            )
        }
    }

    func restoreDefaultSelectionShortcut() {
        assignSelectionShortcut(.selectionDefault)
    }

    func connectSelectionPermissionStatus(_ status: @escaping (Bool) async -> Bool) {
        selectionPermissionStatus = status
        guard selectionPermissionOnboardingPending else { return }
        selectionPermissionOnboardingPending = false
        requestSelectionPermissionOnboardingIfNeeded()
    }

    func refreshSelectionPermission() async {
        guard let selectionPermissionStatus else { return }
        selectionPermissionGranted = await selectionPermissionStatus(false)
    }

    func requestSelectionPermission() async {
        guard let selectionPermissionStatus else { return }
        selectionPermissionGranted = await selectionPermissionStatus(true)
    }

    func dismissSelectionPermissionAlert() {
        selectionPermissionAlertRequested = false
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

    private static func savedShortcut(
        defaults: UserDefaults,
        keyCodeKey: String,
        modifiersKey: String,
        fallback: CaptureShortcut
    ) -> CaptureShortcut {
        guard defaults.object(forKey: keyCodeKey) != nil,
              defaults.object(forKey: modifiersKey) != nil,
              let keyCode = UInt16(exactly: defaults.integer(forKey: keyCodeKey)),
              let modifiers = UInt8(exactly: defaults.integer(forKey: modifiersKey)) else {
            return fallback
        }
        let candidate = CaptureShortcut(
            keyCode: UInt32(keyCode),
            modifiers: ShortcutModifiers(rawValue: modifiers)
        )
        return candidate.isValid ? candidate : fallback
    }

    private func requestSelectionPermissionOnboardingIfNeeded() {
        guard !defaults.bool(forKey: SelectionFailurePresenter.permissionAlertShownKey) else {
            selectionPermissionOnboardingPending = false
            return
        }
        if selectionPermissionGranted == nil {
            guard selectionPermissionStatus != nil else {
                selectionPermissionOnboardingPending = true
                return
            }
            selectionPermissionOnboardingPending = false
            selectionPermissionOnboardingTask?.cancel()
            selectionPermissionOnboardingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await refreshSelectionPermission()
                guard !Task.isCancelled else { return }
                selectionPermissionOnboardingTask = nil
                requestSelectionPermissionOnboardingIfNeeded()
            }
            return
        }
        guard selectionPermissionGranted == false else { return }
        defaults.set(true, forKey: SelectionFailurePresenter.permissionAlertShownKey)
        selectionPermissionAlertRequested = true
    }
}

struct ThoughtboxSettingsView: View {
    @Bindable var model: SettingsModel
    @AccessibilityFocusState private var shortcutErrorFocused: Bool
    @AccessibilityFocusState private var selectionShortcutErrorFocused: Bool
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
                    AccessibleErrorMessage(
                        message: shortcutError,
                        accessibilityLabel: "Settings error: \(shortcutError)",
                        identifier: "settings.shortcut.error"
                    )
                        .accessibilityFocused($shortcutErrorFocused)
                }
            } header: {
                Text(String(localized: "settings.shortcut.section", defaultValue: "Quick Capture"))
            } footer: {
                Text(String(localized: "settings.shortcut.help", defaultValue: "Activate the recorder, then type a shortcut. The change takes effect immediately."))
            }

            Section {
                LabeledContent("Capture Selection Shortcut") {
                    ShortcutRecorderView(
                        shortcut: model.selectionShortcut,
                        identifier: "settings.selectionShortcut.recorder",
                        accessibilityLabel: "Capture Selection shortcut recorder",
                        accessibilityHelp: "Activate, then type the shortcut for adding selected text to the Draft. Press Escape to cancel."
                    ) { shortcut in
                        model.assignSelectionShortcut(shortcut)
                    }
                    .frame(width: 210, height: 28)
                }
                Button("Restore Selection Default") {
                    model.restoreDefaultSelectionShortcut()
                }
                .disabled(model.selectionShortcut == .selectionDefault)
                .help("Reinstates Control–Option–Shift–Space.")
                .accessibilityHint("Reinstates Control–Option–Shift–Space.")
                .accessibilityIdentifier("settings.selectionShortcut.restore")

                LabeledContent("Accessibility Permission") {
                    Text(selectionPermissionLabel)
                        .foregroundStyle(model.selectionPermissionGranted == true ? .green : .secondary)
                        .accessibilityIdentifier("settings.selectionPermission.status")
                }
                Button("Open Accessibility Settings") {
                    requestSelectionPermissionAndOpenSettings()
                }
                .accessibilityHint("Prompts for permission, then opens Privacy and Security settings for Thoughtbox.")
                .accessibilityIdentifier("settings.selectionPermission.openSettings")

                if let error = model.selectionShortcutError {
                    AccessibleErrorMessage(
                        message: error,
                        accessibilityLabel: "Capture Selection shortcut error: \(error)",
                        identifier: "settings.selectionShortcut.error"
                    )
                    .accessibilityFocused($selectionShortcutErrorFocused)
                }
            } header: {
                Text("Capture Selection")
            } footer: {
                Text("Thoughtbox reads only explicitly selected accessible text when you invoke this shortcut. Secure text fields are rejected.")
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
                    AccessibleErrorMessage(
                        message: launchAtLoginError,
                        accessibilityLabel: "Settings error: \(launchAtLoginError)",
                        identifier: "settings.login.error"
                    )
                        .accessibilityFocused($loginErrorFocused)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 520, height: 520)
        .onAppear {
            model.refreshLaunchAtLogin()
            Task { await model.refreshSelectionPermission() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLaunchAtLogin()
            Task { await model.refreshSelectionPermission() }
        }
        .onChange(of: model.shortcutError) { _, error in shortcutErrorFocused = error != nil }
        .onChange(of: model.selectionShortcutError) { _, error in selectionShortcutErrorFocused = error != nil }
        .onChange(of: model.launchAtLoginError) { _, error in loginErrorFocused = error != nil }
        .alert(
            "Allow Selection Capture",
            isPresented: Binding(
                get: { model.selectionPermissionAlertRequested },
                set: { if !$0 { model.dismissSelectionPermissionAlert() } }
            )
        ) {
            Button("Open Accessibility Settings") { requestSelectionPermissionAndOpenSettings() }
            Button("Cancel", role: .cancel) { model.dismissSelectionPermissionAlert() }
        } message: {
            Text("Accessibility permission is required to capture selected text.")
        }
    }

    private var selectionPermissionLabel: String {
        switch model.selectionPermissionGranted {
        case true: "Granted"
        case false: "Required"
        case nil: "Checking…"
        }
    }

    private func requestSelectionPermissionAndOpenSettings() {
        Task { @MainActor in
            await model.requestSelectionPermission()
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: CaptureShortcut
    var identifier = "settings.shortcut.recorder"
    var accessibilityLabel = String(localized: "settings.shortcut.recorderLabel", defaultValue: "Capture shortcut recorder")
    var accessibilityHelp = String(localized: "settings.shortcut.recorderHelp", defaultValue: "Activate, then type the new shortcut. Press Escape to cancel.")
    let onChange: (CaptureShortcut) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(
            shortcut: shortcut,
            identifier: identifier,
            accessibilityLabel: accessibilityLabel,
            accessibilityHelp: accessibilityHelp,
            onChange: context.coordinator.onChange
        )
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

    init(
        shortcut: CaptureShortcut,
        identifier: String,
        accessibilityLabel: String,
        accessibilityHelp: String,
        onChange: @escaping (CaptureShortcut) -> Void
    ) {
        self.shortcut = shortcut
        self.onChange = onChange
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityHelp(accessibilityHelp)
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
