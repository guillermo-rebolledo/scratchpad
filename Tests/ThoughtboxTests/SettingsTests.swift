import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct SettingsTests {
    @Test("Shortcut changes are transactional, persistent, and resettable")
    func shortcutLifecycle() throws {
        let suiteName = "ThoughtboxSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loginItem = TestLoginItemService()
        let model = SettingsModel(defaults: defaults, loginItemService: loginItem)
        var registered: [CaptureShortcut] = []
        model.connectShortcutRegistration { shortcut in
            if shortcut == .init(keyCode: 40, modifiers: [.control, .option]) {
                throw GlobalShortcutError.unavailable
            }
            registered.append(shortcut)
        }

        #expect(model.shortcut == .default)
        #expect(model.shortcut.displayName == "Control–Option–Space")
        #expect(registered == [.default])

        model.assignShortcut(.init(keyCode: 40, modifiers: [.control, .option]))

        #expect(model.shortcut == .default)
        #expect(model.shortcutError != nil)
        #expect(registered == [.default])

        let replacement = CaptureShortcut(keyCode: 38, modifiers: [.control, .option])
        #expect(replacement.displayName(resolvedKeyName: "ñ") == "Control–Option–Ñ")
        model.assignShortcut(replacement)
        #expect(model.shortcut == replacement)
        #expect(model.shortcutError == nil)
        #expect(registered == [.default, replacement])

        let relaunched = SettingsModel(defaults: defaults, loginItemService: loginItem)
        var relaunchedRegistration: CaptureShortcut?
        relaunched.connectShortcutRegistration { relaunchedRegistration = $0 }
        #expect(relaunched.shortcut == replacement)
        #expect(relaunchedRegistration == replacement)

        relaunched.restoreDefaultShortcut()
        #expect(relaunched.shortcut == .default)
        #expect(relaunchedRegistration == .default)

        let modifiedEscape = CaptureShortcut(keyCode: 53, modifiers: [.control, .option])
        relaunched.assignShortcut(modifiedEscape)
        #expect(relaunched.shortcut == modifiedEscape)
        #expect(modifiedEscape.displayName(resolvedKeyName: nil) == "Control–Option–Escape")
    }

    @Test("Capture Selection shortcut is independent, persistent, and resettable")
    func selectionShortcutLifecycle() throws {
        let suiteName = "ThoughtboxSelectionSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsModel(defaults: defaults, loginItemService: TestLoginItemService())
        var quickRegistrations: [CaptureShortcut] = []
        var selectionRegistrations: [CaptureShortcut] = []
        model.connectShortcutRegistration { quickRegistrations.append($0) }
        model.connectSelectionShortcutRegistration { shortcut in
            if shortcut.keyCode == 40 { throw GlobalShortcutError.unavailable }
            selectionRegistrations.append(shortcut)
        }

        #expect(model.shortcut == .default)
        #expect(model.selectionShortcut == .selectionDefault)
        #expect(model.selectionShortcut.displayName == "Control–Option–Shift–Space")
        #expect(quickRegistrations == [.default])
        #expect(selectionRegistrations == [.selectionDefault])

        model.assignSelectionShortcut(.init(keyCode: 40, modifiers: [.control, .option]))
        #expect(model.selectionShortcut == .selectionDefault)
        #expect(model.selectionShortcutError != nil)
        #expect(model.shortcut == .default)

        let replacement = CaptureShortcut(keyCode: 38, modifiers: [.command, .shift])
        model.assignSelectionShortcut(replacement)
        #expect(model.selectionShortcut == replacement)
        #expect(model.selectionShortcutError == nil)
        #expect(model.shortcut == .default)

        let relaunched = SettingsModel(defaults: defaults, loginItemService: TestLoginItemService())
        var restoredRegistration: CaptureShortcut?
        relaunched.connectSelectionShortcutRegistration { restoredRegistration = $0 }
        #expect(relaunched.selectionShortcut == replacement)
        #expect(restoredRegistration == replacement)

        relaunched.restoreDefaultSelectionShortcut()
        #expect(relaunched.selectionShortcut == .selectionDefault)
        #expect(restoredRegistration == .selectionDefault)
    }

    @Test("Launch at Login mirrors system registration and preserves state on failure")
    func launchAtLoginLifecycle() {
        let defaults = UserDefaults(suiteName: "ThoughtboxLoginTests-\(UUID().uuidString)")!
        let loginItem = TestLoginItemService()
        let model = SettingsModel(defaults: defaults, loginItemService: loginItem)

        #expect(model.launchAtLoginEnabled == false)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginEnabled)
        #expect(loginItem.status == .enabled)
        #expect(model.launchAtLoginError == nil)

        loginItem.shouldFail = true
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLoginEnabled)
        #expect(loginItem.status == .enabled)
        #expect(model.launchAtLoginError != nil)

        loginItem.status = .notRegistered
        model.refreshLaunchAtLogin()
        #expect(model.launchAtLoginError == nil)

        loginItem.shouldFail = false
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLoginEnabled == false)
        #expect(loginItem.status == .notRegistered)
    }

    @Test("Malformed persisted shortcut values recover to the default")
    func malformedShortcutPersistence() {
        let defaults = UserDefaults(suiteName: "ThoughtboxMalformedSettings-\(UUID().uuidString)")!
        defaults.set(-1, forKey: "settings.shortcut.keyCode")
        defaults.set(10_000, forKey: "settings.shortcut.modifiers")

        let model = SettingsModel(defaults: defaults, loginItemService: TestLoginItemService())

        #expect(model.shortcut == .default)

        defaults.set(70_000, forKey: "settings.shortcut.keyCode")
        defaults.set(Int(ShortcutModifiers.control.rawValue), forKey: "settings.shortcut.modifiers")
        let oversized = SettingsModel(defaults: defaults, loginItemService: TestLoginItemService())
        #expect(oversized.shortcut == .default)

        defaults.set(-1, forKey: "settings.selectionShortcut.keyCode")
        defaults.set(10_000, forKey: "settings.selectionShortcut.modifiers")
        let malformedSelection = SettingsModel(defaults: defaults, loginItemService: TestLoginItemService())
        #expect(malformedSelection.selectionShortcut == .selectionDefault)
    }

    @Test("Capture Selection permission is checked without prompting and prompted only on request")
    func selectionPermissionLifecycle() async {
        let defaults = UserDefaults(suiteName: "ThoughtboxPermissionSettings-\(UUID().uuidString)")!
        let model = SettingsModel(defaults: defaults, loginItemService: TestLoginItemService())
        var prompts: [Bool] = []
        model.connectSelectionPermissionStatus { prompt in
            prompts.append(prompt)
            return prompt
        }

        await model.refreshSelectionPermission()
        #expect(prompts == [false])
        #expect(model.selectionPermissionGranted == false)

        model.connectSelectionShortcutRegistration { _ in }
        model.assignSelectionShortcut(.init(keyCode: 38, modifiers: [.control, .option, .shift]))
        #expect(model.selectionPermissionAlertRequested)
        model.dismissSelectionPermissionAlert()
        #expect(model.selectionPermissionAlertRequested == false)

        await model.requestSelectionPermission()
        #expect(prompts == [false, true])
        #expect(model.selectionPermissionGranted == true)
    }
}

@MainActor
private final class TestLoginItemService: LoginItemServicing {
    var status: LoginItemStatus = .notRegistered
    var shouldFail = false

    func setEnabled(_ enabled: Bool) throws {
        if shouldFail { throw TestFailure() }
        status = enabled ? .enabled : .notRegistered
    }
}

private struct TestFailure: Error {}
