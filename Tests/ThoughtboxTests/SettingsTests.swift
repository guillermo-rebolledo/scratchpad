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

        loginItem.shouldFail = false
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLoginEnabled == false)
        #expect(loginItem.status == .notRegistered)
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
