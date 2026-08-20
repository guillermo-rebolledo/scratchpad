import XCTest

@MainActor
final class ThoughtboxRealAppAcceptanceTests: XCTestCase {
    func testCaptureAndReviewThroughAccessibility() throws {
        let app = try launch(reset: true)

        let editor = openCapture(in: app)
        XCTAssertEqual(editor.label, "Draft Markdown")
        XCTAssertEqual(editor.value as? String, "Empty")
        editor.typeText("# Durable\n\nCaptured from the real app")
        app.buttons["capture.save"].click()

        let list = app.descendants(matching: .any)["library.thoughts"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["# Durable\n\nCaptured from the real app"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["# Durable\n\nCaptured from the real app"].waitForExistence(timeout: 3))
    }

    func testFailedSaveKeepsDraftAndShowsAccessibleError() throws {
        let app = try launch(reset: true, simulateSaveFailure: true)
        let editor = openCapture(in: app)
        editor.typeText("Do not lose this")
        app.buttons["capture.save"].click()

        XCTAssertEqual(editor.value as? String, "Do not lose this")
        let error = app.descendants(matching: .any)["capture.error"]
        XCTAssertTrue(error.exists)
        XCTAssertTrue(error.label.contains("Your Draft is still here"))
    }

    func testKeyboardSaveNewlineAndWhitespaceValidation() throws {
        let app = try launch(reset: true)
        let editor = openCapture(in: app)
        let saveButton = app.buttons["capture.save"]

        editor.typeText(" \n\t")
        XCTAssertFalse(saveButton.isEnabled)
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        editor.typeText("First line")
        editor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        editor.typeText("Second line")
        editor.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: .command)

        XCTAssertFalse(editor.exists)
        XCTAssertTrue(app.staticTexts["First line\nSecond line"].waitForExistence(timeout: 3))
    }

    func testDraftSurvivesDismissalAndRelaunchUntilConfirmedClear() throws {
        let app = try launch(reset: true)
        var editor = openCapture(in: app)
        editor.typeText("Persistent Draft")
        editor.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        editor = openCapture(in: app)
        XCTAssertEqual(editor.value as? String, "Persistent Draft")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        editor = openCapture(in: app)
        XCTAssertEqual(editor.value as? String, "Persistent Draft")
        let clearButtons = app.buttons.matching(NSPredicate(format: "label == 'Clear Draft'"))
        clearButtons.firstMatch.click()
        XCTAssertTrue(clearButtons.element(boundBy: 1).waitForExistence(timeout: 3))
        let destructiveClear = clearButtons.element(boundBy: 1)
        destructiveClear.click()
        XCTAssertEqual(editor.value as? String, "Empty")
    }

    func testGlobalShortcutOpensCaptureOutsideThoughtbox() throws {
        let app = try launch(reset: true)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey(XCUIKeyboardKey.space.rawValue, modifierFlags: [.control, .option])

        XCTAssertTrue(app.textViews["capture.editor"].waitForExistence(timeout: 3))
    }

    func testMainWindowClosesWithoutTerminatingCaptureService() throws {
        let app = try launch(reset: true)
        XCTAssertEqual(app.windows.count, 1)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, 0)

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textViews["capture.editor"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func application() throws -> XCUIApplication {
        if let path = ProcessInfo.processInfo.environment["THOUGHTBOX_APP_PATH"] {
            return XCUIApplication(url: URL(fileURLWithPath: path, isDirectory: true))
        }
        return XCUIApplication()
    }

    private func launch(reset: Bool, simulateSaveFailure: Bool = false) throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["THOUGHTBOX_RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Run this file from the Xcode Thoughtbox UI-test scheme.")
        }

        let app = try application()
        app.launchEnvironment["THOUGHTBOX_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]
        if reset { app.launchArguments.append("--reset-ui-test-store") }
        if simulateSaveFailure { app.launchArguments.append("--simulate-save-failure") }
        app.launch()
        return app
    }

    private func openCapture(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("n", modifierFlags: .command)
        let editor = app.textViews["capture.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        return editor
    }
}
