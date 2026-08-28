import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct StatusMenuTests {
    @Test("Unified status menu wires every task and updates configurable shortcuts")
    func unifiedMenuConfiguration() async throws {
        let repository = try ThoughtRepository.inMemory()
        let suiteName = "ThoughtboxStatusMenuTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = CaptureController(
            container: repository.container,
            draft: DraftStore(defaults: defaults),
            statusItem: NSStatusItem()
        )
        var invoked: [String] = []

        controller.configureStatusMenu(
            quickCaptureShortcut: .default,
            selectionShortcut: .selectionDefault,
            openThoughtShortcut: .menuBarThoughtDefault,
            captureSelection: { invoked.append("selection") },
            openThought: { invoked.append("thought") },
            openLibrary: { invoked.append("library") },
            openSettings: { invoked.append("settings") },
            checkForUpdates: { invoked.append("updates") }
        )

        let menu = try #require(controller.statusItem.menu)
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "New Thought",
            "Capture Selection",
            "Open Thought",
            "Open Thoughtbox",
            "Settings…",
            "Check for Updates…",
            "Quit Thoughtbox"
        ])
        #expect(menu.item(withTitle: "New Thought")?.action?.description == "openCaptureFromMenu")
        #expect(menu.item(withTitle: "Quit Thoughtbox")?.action?.description == "quitFromMenu")
        #expect(menu.item(withTitle: "Open Thoughtbox")?.keyEquivalent == "o")
        #expect(menu.item(withTitle: "Settings…")?.keyEquivalent == ",")
        #expect(menu.item(withTitle: "Check for Updates…")?.keyEquivalentModifierMask == [.command, .shift])
        #expect(menu.item(withTitle: "Quit Thoughtbox")?.keyEquivalent == "q")

        try invoke("Capture Selection", in: menu)
        try invoke("Open Thought", in: menu)
        try await Task.sleep(for: .milliseconds(10))
        try invoke("Open Thoughtbox", in: menu)
        try invoke("Settings…", in: menu)
        try invoke("Check for Updates…", in: menu)
        #expect(invoked == ["selection", "thought", "library", "settings", "updates"])

        let replacement = CaptureShortcut(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: [.command, .shift]
        )
        controller.updateStatusMenuShortcut(replacement, for: .quickCapture)
        #expect(menu.item(withTitle: "New Thought")?.keyEquivalent == "n")
        #expect(menu.item(withTitle: "New Thought")?.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("Menu shortcut equivalents support recorded special keys and missing layouts")
    func specialKeyEquivalents() {
        let modifiers: ShortcutModifiers = [.control, .option, .shift, .command]
        #expect(modifiers.eventFlags == [.control, .option, .shift, .command])
        #expect(CaptureShortcut(keyCode: UInt32(kVK_Return), modifiers: []).menuKeyEquivalent == "\r")
        #expect(CaptureShortcut(keyCode: UInt32(kVK_Tab), modifiers: []).menuKeyEquivalent == "\t")
        #expect(CaptureShortcut(keyCode: UInt32(kVK_Escape), modifiers: []).menuKeyEquivalent == "\u{1b}")
        #expect(CaptureShortcut(keyCode: UInt32(kVK_Delete), modifiers: []).menuKeyEquivalent == "\u{8}")
        #expect(
            CaptureShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: []).menuKeyEquivalent
                == String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        )
        #expect(CaptureShortcut(keyCode: 65_535, modifiers: []).menuKeyEquivalent(resolvedKeyName: nil).isEmpty)
    }

    private func invoke(_ title: String, in menu: NSMenu) throws {
        let item = try #require(menu.item(withTitle: title))
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
    }
}
