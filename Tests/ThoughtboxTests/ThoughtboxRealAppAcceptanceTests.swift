import XCTest

@MainActor
final class ThoughtboxRealAppAcceptanceTests: XCTestCase {
    func testCaptureAndReviewThroughAccessibility() throws {
        guard ProcessInfo.processInfo.environment["THOUGHTBOX_RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Set THOUGHTBOX_RUN_UI_TESTS=1 from the Xcode UI-test scheme.")
        }

        let app = try application()
        let session = UUID().uuidString
        app.launchEnvironment["THOUGHTBOX_UI_TEST_SESSION"] = session
        app.launchArguments = ["--ui-testing", "--reset-ui-test-store"]
        app.launch()

        app.typeKey("n", modifierFlags: .command)
        let editor = app.textViews["capture.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("# Durable\n\nCaptured from the real app")
        app.buttons["capture.save"].click()

        let list = app.outlines["library.thoughts"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["# Durable\n\nCaptured from the real app"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["# Durable\n\nCaptured from the real app"].waitForExistence(timeout: 3))
    }

    func testFailedSaveKeepsDraftAndShowsAccessibleError() throws {
        guard ProcessInfo.processInfo.environment["THOUGHTBOX_RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Set THOUGHTBOX_RUN_UI_TESTS=1 from the Xcode UI-test scheme.")
        }

        let app = try application()
        app.launchEnvironment["THOUGHTBOX_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--reset-ui-test-store", "--simulate-save-failure"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let editor = app.textViews["capture.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Do not lose this")
        app.buttons["capture.save"].click()

        XCTAssertEqual(editor.value as? String, "Do not lose this")
        XCTAssertTrue(app.staticTexts["capture.error"].exists)
    }

    private func application() throws -> XCUIApplication {
        if let path = ProcessInfo.processInfo.environment["THOUGHTBOX_APP_PATH"] {
            return XCUIApplication(url: URL(fileURLWithPath: path, isDirectory: true))
        }
        return XCUIApplication()
    }
}
