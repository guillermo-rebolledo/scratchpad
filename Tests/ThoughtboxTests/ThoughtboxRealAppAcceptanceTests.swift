import XCTest

@MainActor
final class ThoughtboxRealAppAcceptanceTests: XCTestCase {
    func testCheckForUpdatesCommandIsKeyboardAndAccessibilityReachable() throws {
        let app = try launch(reset: true)
        let appMenu = app.menuBars.menuBarItems["Thoughtbox"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 3))
        appMenu.click()
        let command = app.menuItems["Check for Updates…"]
        XCTAssertTrue(command.waitForExistence(timeout: 3))
        XCTAssertTrue(command.isEnabled)
    }

    func testStagedSparkleUpdatePreservesAllLocalData() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["THOUGHTBOX_RUN_UPDATE_TEST"] == "1" else {
            throw XCTSkip("Run through Scripts/release/verify-staged-update.sh on a clean Mac.")
        }
        let stagedAppcast = try XCTUnwrap(environment["THOUGHTBOX_STAGED_APPCAST_URL"])
        let expectedVersion = try XCTUnwrap(environment["THOUGHTBOX_EXPECTED_UPDATE_VERSION"])
        let app = try application()
        app.launchArguments = ["--test-sparkle-update", "-SUFeedURL", stagedAppcast]
        app.launch()

        createProject("Update Project", in: app)
        capture("Inbox survives update", in: app)
        capture("Project Thought survives update", destination: "Update Project", in: app)
        capture("Trash survives update", destination: "Update Project", in: app)
        app.staticTexts["Trash survives update"].click()
        app.buttons["trash.move"].click()

        let editor = openCapture(in: app)
        choose("Update Project", from: "capture.destination", in: app)
        editor.typeText("Draft survives update")
        editor.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        let recorder = openSettings(in: app)
        recorder.click()
        recorder.typeKey("j", modifierFlags: [.control, .option])
        XCTAssertEqual(recorder.value as? String, "Control–Option–J")
        app.typeKey("w", modifierFlags: .command)

        let appMenu = app.menuBars.menuBarItems["Thoughtbox"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 3))
        appMenu.click()
        let checkCommand = app.menuItems["Check for Updates…"]
        XCTAssertTrue(checkCommand.waitForExistence(timeout: 3))
        checkCommand.click()

        let installUpdate = app.buttons["Install Update"]
        XCTAssertTrue(installUpdate.waitForExistence(timeout: 60))
        installUpdate.click()
        let installAndRelaunch = app.buttons["Install and Relaunch"]
        XCTAssertTrue(installAndRelaunch.waitForExistence(timeout: 180))
        installAndRelaunch.click()

        let appPath = try XCTUnwrap(environment["THOUGHTBOX_APP_PATH"])
        XCTAssertTrue(waitForVersion(expectedVersion, in: appPath, timeout: 180))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60))
        XCTAssertTrue(app.staticTexts["Inbox survives update"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Project Thought survives update"].exists)
        XCTAssertTrue(app.staticTexts["Update Project"].exists)

        app.descendants(matching: .any)["trash.sidebar"].click()
        XCTAssertTrue(app.staticTexts["Trash survives update"].waitForExistence(timeout: 3))

        let relaunchedDraft = openCapture(in: app)
        XCTAssertEqual(relaunchedDraft.value as? String, "Draft survives update")
        XCTAssertEqual(
            app.descendants(matching: .any)["capture.destination"].value as? String,
            "Update Project"
        )
        relaunchedDraft.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        let relaunchedRecorder = openSettings(in: app)
        XCTAssertEqual(relaunchedRecorder.value as? String, "Control–Option–J")
    }

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

    func testLibraryAdaptsAtMinimumWindowSizeAndRestoresItsSidebar() throws {
        let app = try launch(reset: true)
        capture("Minimum boundary Thought", in: app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        let resizeHandle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
        let undersizedTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        resizeHandle.press(forDuration: 0.1, thenDragTo: undersizedTarget, withVelocity: .slow, thenHoldForDuration: 0)

        XCTAssertGreaterThanOrEqual(window.frame.width, 840)
        XCTAssertGreaterThanOrEqual(window.frame.height, 540)
        XCTAssertTrue(app.descendants(matching: .any)["library.sidebar.all"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["library.thoughts"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["thought.detail"].isHittable)

        let destination = app.descendants(matching: .any)["thought.destination"]
        let edit = app.buttons["thought.edit"]
        XCTAssertTrue(destination.isHittable)
        XCTAssertTrue(edit.isHittable)
        XCTAssertEqual(destination.label, "Thought destination")
        XCTAssertEqual(edit.label, "Edit Thought")

        let sidebarToggle = app.buttons["Toggle Sidebar"]
        XCTAssertTrue(sidebarToggle.isHittable)
        sidebarToggle.click()
        XCTAssertFalse(app.descendants(matching: .any)["library.sidebar.all"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["library.thoughts"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["thought.detail"].isHittable)

        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 3))
        viewMenu.click()
        let showSidebar = app.menuItems["Show Sidebar"]
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 3))
        showSidebar.click()
        XCTAssertTrue(app.descendants(matching: .any)["library.sidebar.all"].waitForExistence(timeout: 3))

        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertFalse(app.descendants(matching: .any)["library.sidebar.all"].isHittable)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(app.descendants(matching: .any)["library.sidebar.all"].waitForExistence(timeout: 3))
    }

    func testFailedSaveKeepsDraftAndShowsAccessibleError() throws {
        let app = try launch(reset: true, simulateSaveFailure: true)
        let editor = openCapture(in: app)
        editor.typeText("Do not lose this")
        app.buttons["capture.save"].click()

        XCTAssertEqual(editor.value as? String, "Do not lose this")
        let error = app.descendants(matching: .any)["capture.error"]
        XCTAssertTrue(error.exists)
        XCTAssertTrue(error.label.contains("Save error"))
        XCTAssertTrue(accessibilityText(of: error).contains("Your Draft is still here"))
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

    func testShortcutSettingsRejectConflictActivatePersistAndRestore() throws {
        let app = try launch(reset: true, additionalArguments: ["--simulate-shortcut-conflict"])
        var recorder = openSettings(in: app)
        XCTAssertEqual(recorder.value as? String, "Control–Option–Space")

        app.typeKey(XCUIKeyboardKey.space.rawValue, modifierFlags: [])
        app.typeKey("k", modifierFlags: [.control, .option])
        let conflict = app.descendants(matching: .any)["settings.shortcut.error"]
        XCTAssertTrue(conflict.waitForExistence(timeout: 3))
        XCTAssertTrue(conflict.label.contains("Settings error"))
        XCTAssertTrue(accessibilityText(of: conflict).contains("previous shortcut is still active"))
        XCTAssertEqual(recorder.value as? String, "Control–Option–Space")

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey(XCUIKeyboardKey.space.rawValue, modifierFlags: [.control, .option])
        XCTAssertTrue(app.textViews["capture.editor"].waitForExistence(timeout: 3))
        app.textViews["capture.editor"].typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.activate()
        recorder = openSettings(in: app)

        recorder.click()
        recorder.typeKey("j", modifierFlags: [.control, .option])
        XCTAssertEqual(recorder.value as? String, "Control–Option–J")
        finder.activate()
        finder.typeKey("j", modifierFlags: [.control, .option])
        XCTAssertTrue(app.textViews["capture.editor"].waitForExistence(timeout: 3))
        app.textViews["capture.editor"].typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        recorder = openSettings(in: app)
        XCTAssertEqual(recorder.value as? String, "Control–Option–J")

        app.buttons["settings.shortcut.restore"].click()
        XCTAssertEqual(recorder.value as? String, "Control–Option–Space")
        finder.activate()
        finder.typeKey(XCUIKeyboardKey.space.rawValue, modifierFlags: [.control, .option])
        XCTAssertTrue(app.textViews["capture.editor"].waitForExistence(timeout: 3))
    }

    func testLaunchAtLoginOptInOutPersistenceAndFailure() throws {
        var app = try launch(reset: true)
        _ = openSettings(in: app)
        var toggle = app.descendants(matching: .any)["settings.login.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertFalse(controlIsOn(toggle))
        toggle.click()
        XCTAssertTrue(controlIsOn(toggle))

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        _ = openSettings(in: app)
        toggle = app.descendants(matching: .any)["settings.login.toggle"]
        XCTAssertTrue(controlIsOn(toggle))
        toggle.click()
        XCTAssertFalse(controlIsOn(toggle))

        app.terminate()
        app = try launch(reset: true, additionalArguments: ["--simulate-login-item-failure"])
        _ = openSettings(in: app)
        toggle = app.descendants(matching: .any)["settings.login.toggle"]
        toggle.click()
        XCTAssertFalse(controlIsOn(toggle))
        let error = app.descendants(matching: .any)["settings.login.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue(error.label.contains("Settings error"))
        XCTAssertTrue(accessibilityText(of: error).contains("system setting was not changed"))
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

    func testMarkdownRendersSupportedBlocksWithoutImages() throws {
        let app = try launch(
            reset: true,
            additionalArguments: [
                "-NSAutomaticDashSubstitutionEnabled", "NO",
                "-NSAutomaticQuoteSubstitutionEnabled", "NO"
            ]
        )
        capture(
            """
            # Rendered heading

            **Bold** and ~~finished~~ with [Example](https://example.com) and ![private](https://tracker.example/pixel.png).

            > Quoted

            - [ ] Visual task

            | Name | Value |
            | --- | --- |
            | One | Two |

            ```swift
            let answer = 42
            ```
            """,
            in: app
        )

        XCTAssertTrue(app.staticTexts["Rendered heading"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts.matching(identifier: "markdown.paragraph").matching(
                NSPredicate(
                    format: "label CONTAINS %@ OR value CONTAINS %@",
                    "Image not loaded: private",
                    "Image not loaded: private"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(app.images["private"].exists)
        XCTAssertFalse(app.staticTexts["https://tracker.example/pixel.png"].exists)
        let externalLink = app.links["Example"]
        XCTAssertTrue(externalLink.exists)
        XCTAssertTrue(externalLink.isHittable)
        externalLink.click()
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate()
        let table = app.groups.matching(
            NSPredicate(format: "label == %@", "Table with 2 columns and 1 rows")
        ).firstMatch
        XCTAssertTrue(table.exists, app.debugDescription)
    }

    func testEditAutoSavesAndSurvivesRelaunch() throws {
        let app = try launch(reset: true)
        capture("Before edit", in: app)

        let thoughtMenu = app.menuBars.menuBarItems["Thought"]
        XCTAssertTrue(thoughtMenu.waitForExistence(timeout: 3))
        thoughtMenu.click()
        XCTAssertTrue(app.menuItems["Edit Thought"].isEnabled)
        XCTAssertTrue(app.menuItems["Move Thought To"].isEnabled)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.typeKey("e", modifierFlags: [.command, .control])
        let editor = app.textViews["thought.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["thought.edit"].label, "Done Editing")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("After edit")
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["thought.save.status"], containing: "Changes saved"))
        app.buttons["thought.edit"].click()
        XCTAssertTrue(app.staticTexts["After edit"].exists)
        XCTAssertTrue(app.buttons["thought.edit"].isHittable)
        XCTAssertEqual(app.buttons["thought.edit"].label, "Edit Thought")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["After edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["thought.edited.at"].exists)
    }

    func testThoughtEditErrorKeepsAccessibleRecoveryGuidance() throws {
        let app = try launch(reset: true)
        capture("Thought cannot become blank", in: app)

        app.buttons["thought.edit"].click()
        let editor = app.textViews["thought.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        app.buttons["thought.edit"].click()

        let error = app.descendants(matching: .any)["thought.edit.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue(error.label.contains("Edit error"))
        XCTAssertTrue(error.label.contains("Restore non-empty content or retry"))
        XCTAssertTrue(editor.exists)
    }

    func testEditingOlderThoughtDoesNotChangeCreationOrder() throws {
        let app = try launch(reset: true)
        capture("Older Thought", in: app)
        capture("Newer Thought", in: app)

        let newerRow = thoughtRow("Newer Thought", in: app)
        let olderRow = thoughtRow("Older Thought", in: app)
        XCTAssertLessThan(newerRow.frame.minY, olderRow.frame.minY)
        olderRow.click()
        app.buttons["thought.edit"].click()
        let editor = app.textViews["thought.editor"]
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Older Thought edited")
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["thought.save.status"], containing: "Changes saved"))

        XCTAssertLessThan(newerRow.frame.minY, thoughtRow("Older Thought edited", in: app).frame.minY)
    }

    func testEditSavesImmediatelyOnFocusAndThoughtSelectionChanges() throws {
        let app = try launch(reset: true)
        capture("First Thought", in: app)
        capture("Second Thought", in: app)

        thoughtRow("First Thought", in: app).click()
        app.buttons["thought.edit"].click()
        var editor = app.textViews["thought.editor"]
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Saved by selection")
        thoughtRow("Second Thought", in: app).click()
        thoughtRow("Saved by selection", in: app).click()
        XCTAssertTrue(thoughtRow("Saved by selection", in: app).exists)

        app.buttons["thought.edit"].click()
        editor = app.textViews["thought.editor"]
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Saved by focus")
        app.buttons["thought.edit"].click()
        XCTAssertTrue(thoughtRow("Saved by focus", in: app).waitForExistence(timeout: 3))
    }

    func testProjectCreationNormalizedUniquenessOrderingAndRename() throws {
        let app = try launch(reset: true)
        createProject(" Older Project ", in: app)
        createProject("Newer Project", in: app)

        let newer = element(labeled: "Newer Project", in: app)
        let older = element(labeled: "Older Project", in: app)
        XCTAssertTrue(newer.exists)
        XCTAssertTrue(older.exists)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY)
        XCTAssertEqual(app.buttons["project.create"].label, "New Project")
        XCTAssertFalse(app.buttons["project.rename"].exists)
        XCTAssertFalse(app.buttons["project.delete"].exists)

        app.buttons["project.create"].click()
        let name = app.textFields["project.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("older project")
        app.buttons["project.save"].click()
        let duplicateError = app.descendants(matching: .any)["project.error"]
        XCTAssertTrue(duplicateError.waitForExistence(timeout: 3))
        XCTAssertTrue(duplicateError.label.contains("Project error"))
        XCTAssertTrue(accessibilityText(of: duplicateError).contains("without regard to capitalization"))
        app.buttons["Cancel"].click()

        older.rightClick()
        let renameProject = app.menuItems["Rename Project"]
        XCTAssertTrue(renameProject.waitForExistence(timeout: 3))
        renameProject.click()
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Renamed Project")
        app.buttons["project.save"].click()

        let renamed = element(labeled: "Renamed Project", in: app)
        XCTAssertTrue(renamed.waitForExistence(timeout: 3))
        XCTAssertLessThan(newer.frame.minY, renamed.frame.minY)
    }

    func testProjectNavigationReassignmentAndInboxFiltering() throws {
        let app = try launch(reset: true)
        createProject("Work", in: app)

        let editor = openCapture(in: app)
        choose("Work", from: "capture.destination", in: app)
        editor.typeText("Project Thought")
        app.buttons["capture.save"].click()
        XCTAssertFalse(editor.exists)

        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Inbox Is Empty"].waitForExistence(timeout: 3))
        app.staticTexts["Work"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Project Thought"].waitForExistence(timeout: 3))

        choose("Inbox", from: "thought.destination", in: app)
        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Project Thought"].waitForExistence(timeout: 3))

        app.staticTexts["All Thoughts"].firstMatch.click()
        XCTAssertTrue(accessibilityText(of: thoughtRow("Project Thought", in: app)).contains("in Inbox"))
    }

    func testThoughtRowsExposeCanonicalExcerptAndCompactCollectionContext() throws {
        let app = try launch(reset: true)
        let longProjectName = "A Project Name Long Enough to Require Predictable Truncation"
        let longMarkdown = String(repeating: "Long canonical Markdown content ", count: 12)
        createProject(longProjectName, in: app)
        capture("Inbox Thought", in: app)
        capture("Project Thought", destination: longProjectName, in: app)
        capture("Duplicate Thought", in: app)
        capture("Duplicate Thought", in: app)
        capture(longMarkdown, destination: longProjectName, in: app)

        app.staticTexts["All Thoughts"].firstMatch.click()
        let list = app.descendants(matching: .any)["library.thoughts"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        let inboxRow = thoughtRow("Inbox Thought", in: app)
        let projectRow = thoughtRow("Project Thought", in: app)
        XCTAssertTrue(accessibilityText(of: inboxRow).contains("created"))
        XCTAssertTrue(accessibilityText(of: inboxRow).contains("Inbox"))
        XCTAssertTrue(accessibilityText(of: projectRow).contains(longProjectName))
        XCTAssertEqual(
            list.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Duplicate Thought", "Duplicate Thought")).count,
            2
        )
        let longRow = thoughtRow(longMarkdown, in: app)
        XCTAssertLessThanOrEqual(longRow.frame.maxX, list.frame.maxX + 1)

        app.staticTexts[longProjectName].firstMatch.click()
        XCTAssertTrue(accessibilityText(of: thoughtRow("Project Thought", in: app)).contains(longProjectName))

        app.staticTexts["All Thoughts"].firstMatch.click()
        inboxRow.click()
        app.buttons["trash.move"].click()
        app.descendants(matching: .any)["trash.sidebar"].click()
        XCTAssertTrue(accessibilityText(of: thoughtRow("Inbox Thought", in: app)).contains("Trash"))
    }

    func testDraftProjectDestinationPersistsAndResetsAfterCapture() throws {
        let app = try launch(reset: true)
        createProject("Persistent Destination", in: app)

        var editor = openCapture(in: app)
        choose("Persistent Destination", from: "capture.destination", in: app)
        editor.typeText("Destination Draft")
        editor.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        editor = openCapture(in: app)
        XCTAssertEqual(app.descendants(matching: .any)["capture.destination"].value as? String, "Persistent Destination")
        app.buttons["capture.save"].click()

        _ = openCapture(in: app)
        XCTAssertEqual(app.descendants(matching: .any)["capture.destination"].value as? String, "Inbox")
    }

    func testSearchFiltersAllInboxAndProjectScopesAndClearsInPlace() throws {
        let app = try launch(reset: true)
        createProject("Search Project", in: app)
        capture("Project SearchNeedle", destination: "Search Project", in: app)
        capture("Project other content", destination: "Search Project", in: app)
        capture("Inbox SearchNeedle", in: app)

        app.staticTexts["All Thoughts"].firstMatch.click()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("SearchNeedle")
        XCTAssertTrue(app.staticTexts["Project SearchNeedle"].exists)
        XCTAssertTrue(app.staticTexts["Inbox SearchNeedle"].exists)
        XCTAssertFalse(app.staticTexts["Project other content"].exists)

        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Inbox SearchNeedle"].exists)
        XCTAssertFalse(app.staticTexts["Project SearchNeedle"].exists)

        app.staticTexts["Search Project"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Project SearchNeedle"].exists)
        XCTAssertFalse(app.staticTexts["Inbox SearchNeedle"].exists)

        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Project other content"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows["main"].title, "Search Project")

        search.click()
        search.typeText("No matching Thought")
        XCTAssertTrue(app.staticTexts["No Search Results"].waitForExistence(timeout: 3))
    }

    func testEmptyCollectionsOfferActionsThatResolveTheirCurrentScope() throws {
        let app = try launch(reset: true)

        XCTAssertTrue(app.staticTexts["No Thoughts Yet"].waitForExistence(timeout: 3))
        var captureAction = app.descendants(matching: .any)["library.empty.capture"]
        XCTAssertTrue(captureAction.isHittable)
        XCTAssertEqual(captureAction.label, "Capture Thought")
        captureAction.click()
        var editor = app.textViews["capture.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Captured from empty All Thoughts")
        app.buttons["capture.save"].click()
        XCTAssertTrue(thoughtRow("Captured from empty All Thoughts", in: app).waitForExistence(timeout: 3))

        app.descendants(matching: .any)["trash.sidebar"].click()
        XCTAssertTrue(app.staticTexts["Trash Is Empty"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["library.empty.capture"].exists)

        app.staticTexts["All Thoughts"].firstMatch.click()
        createProject("Empty Action Project", in: app)
        XCTAssertTrue(app.staticTexts["Project Is Empty"].waitForExistence(timeout: 3))
        captureAction = app.descendants(matching: .any)["library.empty.capture"]
        XCTAssertEqual(captureAction.label, "Capture to Empty Action Project")
        captureAction.click()
        editor = app.textViews["capture.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.descendants(matching: .any)["capture.destination"].value as? String,
            "Empty Action Project"
        )
        editor.typeText("Project Draft from empty state")
        editor.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        editor = openCapture(in: app)
        XCTAssertEqual(editor.value as? String, "Project Draft from empty state")
        XCTAssertEqual(
            app.descendants(matching: .any)["capture.destination"].value as? String,
            "Empty Action Project"
        )
        app.buttons["capture.save"].click()
        XCTAssertTrue(thoughtRow("Project Draft from empty state", in: app).waitForExistence(timeout: 3))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("No matching Thought")
        XCTAssertTrue(app.staticTexts["No Search Results"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["library.empty.capture"].exists)
        let clearSearch = app.descendants(matching: .any)["library.empty.clearSearch"]
        XCTAssertTrue(clearSearch.isHittable)
        clearSearch.click()
        XCTAssertTrue(thoughtRow("Project Draft from empty state", in: app).waitForExistence(timeout: 3))
    }

    func testKeyboardMultiSelectionBulkMoveAndRelaunchPersistence() throws {
        let app = try launch(reset: true)
        createProject("Bulk Source", in: app)
        capture("Older Bulk Thought", destination: "Bulk Source", in: app)
        capture("Newer Bulk Thought", destination: "Bulk Source", in: app)

        app.staticTexts["Bulk Source"].firstMatch.click()
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        let selectionCount = app.descendants(matching: .any)["bulk.selection.count"]
        XCTAssertTrue(selectionCount.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibilityText(of: selectionCount).contains("2 Thoughts selected"))

        let moveMenu = app.descendants(matching: .any)["bulk.destination"]
        XCTAssertTrue(moveMenu.waitForExistence(timeout: 3))
        moveMenu.click()
        let inboxDestination = app.menuItems["Inbox"]
        XCTAssertTrue(inboxDestination.waitForExistence(timeout: 3))
        inboxDestination.click()
        XCTAssertTrue(app.descendants(matching: .any)["bulk.status"].waitForExistence(timeout: 3))

        app.staticTexts["Inbox"].firstMatch.click()
        let newer = thoughtRow("Newer Bulk Thought", in: app)
        let older = thoughtRow("Older Bulk Thought", in: app)
        XCTAssertTrue(newer.exists)
        XCTAssertTrue(older.exists)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(thoughtRow("Newer Bulk Thought", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(thoughtRow("Older Bulk Thought", in: app).exists)
    }

    func testKeyboardSearchAndSelectionAnnouncements() throws {
        let app = try launch(reset: true)
        capture("Keyboard Search Result", in: app)
        capture("Keyboard Other Result", in: app)

        app.typeKey("f", modifierFlags: .command)
        app.typeText("Keyboard Search")
        XCTAssertTrue(app.staticTexts["Keyboard Search Result"].waitForExistence(timeout: 3))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        let selectionCount = app.descendants(matching: .any)["bulk.selection.count"]
        XCTAssertTrue(selectionCount.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibilityText(of: selectionCount).contains("2 Thoughts selected"))
    }

    func testFailedBulkMoveReportsErrorWithoutPartialMovement() throws {
        let app = try launch(reset: true, simulateBulkMoveFailure: true)
        createProject("Failure Source", in: app)
        capture("First Failure Thought", destination: "Failure Source", in: app)
        capture("Second Failure Thought", destination: "Failure Source", in: app)

        app.staticTexts["Failure Source"].firstMatch.click()
        app.staticTexts["Second Failure Thought"].click()
        app.typeKey("a", modifierFlags: .command)
        choose("Inbox", from: "bulk.destination", in: app)

        let error = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue(error.label.contains("Library error"))
        XCTAssertTrue(error.label.contains("could not move"))
        XCTAssertTrue(app.staticTexts["First Failure Thought"].exists)
        XCTAssertTrue(app.staticTexts["Second Failure Thought"].exists)
        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Inbox Is Empty"].waitForExistence(timeout: 3))
    }

    func testSingleAndBulkTrashSearchRestoreAndRelaunchRetention() throws {
        let app = try launch(reset: true)
        createProject("Trash Source", in: app)
        capture("Oldest Trash Thought", destination: "Trash Source", in: app)
        capture("Middle Trash Thought", destination: "Trash Source", in: app)
        capture("Newest Trash SearchNeedle", destination: "Trash Source", in: app)

        app.staticTexts["Trash Source"].firstMatch.click()
        thoughtRow("Oldest Trash Thought", in: app).click()
        app.buttons["trash.move"].click()
        XCTAssertTrue(app.descendants(matching: .any)["bulk.status"].label.contains("Moved 1 Thought"))

        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        XCTAssertTrue(accessibilityText(of: app.descendants(matching: .any)["bulk.selection.count"]).contains("2 Thoughts selected"))
        app.buttons["trash.move"].click()

        app.descendants(matching: .any)["trash.sidebar"].click()
        let newest = thoughtRow("Newest Trash SearchNeedle", in: app)
        let middle = thoughtRow("Middle Trash Thought", in: app)
        let oldest = thoughtRow("Oldest Trash Thought", in: app)
        XCTAssertTrue(newest.waitForExistence(timeout: 3))
        XCTAssertLessThan(newest.frame.minY, middle.frame.minY)
        XCTAssertLessThan(middle.frame.minY, oldest.frame.minY)

        let search = app.searchFields.firstMatch
        search.click()
        search.typeText("SearchNeedle")
        XCTAssertTrue(newest.exists)
        XCTAssertFalse(middle.exists)
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        capture("First Bulk Permanent Thought", in: app)
        capture("Second Bulk Permanent Thought", in: app)
        app.staticTexts["Inbox"].firstMatch.click()
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.move"].click()
        app.descendants(matching: .any)["trash.sidebar"].click()
        let trashSearch = app.searchFields.firstMatch
        trashSearch.click()
        trashSearch.typeText("Bulk Permanent")
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.delete"].click()
        XCTAssertTrue(app.staticTexts["Permanently delete 2 Thoughts?"].waitForExistence(timeout: 3))
        app.buttons["trash.delete.confirm"].click()
        XCTAssertTrue(app.staticTexts["No Search Results"].waitForExistence(timeout: 3))
        trashSearch.typeKey("a", modifierFlags: .command)
        trashSearch.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.descendants(matching: .any)["trash.sidebar"].click()
        XCTAssertTrue(thoughtRow("Newest Trash SearchNeedle", in: app).waitForExistence(timeout: 3))
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.restore"].click()

        app.staticTexts["Trash Source"].firstMatch.click()
        XCTAssertTrue(thoughtRow("Newest Trash SearchNeedle", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(thoughtRow("Middle Trash Thought", in: app).exists)
        XCTAssertTrue(thoughtRow("Oldest Trash Thought", in: app).exists)
    }

    func testProjectDeleteConstraintDraftFallbackRestoreFallbackAndPermanentDelete() throws {
        let app = try launch(reset: true)
        createProject("Disposable Project", in: app)
        capture("Disposable Thought", destination: "Disposable Project", in: app)

        app.staticTexts["Disposable Project"].firstMatch.click()
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [.command, .option])
        let status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.label.contains("Move or delete it before deleting the Project"))

        let editor = openCapture(in: app)
        choose("Disposable Project", from: "capture.destination", in: app)
        editor.typeText("Draft remains intact")
        editor.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        thoughtRow("Disposable Thought", in: app).click()
        app.buttons["trash.move"].click()
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [.command, .option])
        XCTAssertTrue(app.buttons["project.delete.confirm"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'formerly belonged' OR value CONTAINS 'formerly belonged'"))
                .firstMatch
                .waitForExistence(timeout: 3)
        )
        app.buttons["project.delete.confirm"].click()
        XCTAssertFalse(app.staticTexts["Disposable Project"].firstMatch.exists)
        XCTAssertTrue(status.label.contains("Draft is intact"))

        let restoredDraft = openCapture(in: app)
        XCTAssertEqual(restoredDraft.value as? String, "Draft remains intact")
        XCTAssertEqual(app.descendants(matching: .any)["capture.destination"].value as? String, "Inbox")
        XCTAssertTrue(app.descendants(matching: .any)["capture.destination.notice"].exists)
        restoredDraft.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.descendants(matching: .any)["trash.sidebar"].click()
        thoughtRow("Disposable Thought", in: app).click()
        app.buttons["trash.restore"].click()
        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Disposable Thought"].waitForExistence(timeout: 3))

        app.buttons["trash.move"].click()
        app.descendants(matching: .any)["trash.sidebar"].click()
        thoughtRow("Disposable Thought", in: app).click()
        app.buttons["trash.delete"].click()
        XCTAssertTrue(app.buttons["trash.delete.confirm"].waitForExistence(timeout: 3))
        app.buttons["trash.delete.confirm"].click()
        XCTAssertTrue(app.staticTexts["Trash Is Empty"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.descendants(matching: .any)["trash.sidebar"].click()
        XCTAssertTrue(app.staticTexts["Trash Is Empty"].waitForExistence(timeout: 3))
    }

    func testTrashOperationFailuresAreAccessibleAndRecoverableAcrossRelaunch() throws {
        let app = try launch(reset: true, additionalArguments: ["--simulate-trash-failure"])
        capture("First recoverable Thought", in: app)
        capture("Second recoverable Thought", in: app)
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.move"].click()
        var status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.label.contains("Nothing was moved"))
        XCTAssertTrue(app.staticTexts["First recoverable Thought"].exists)
        XCTAssertTrue(app.staticTexts["Second recoverable Thought"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.move"].click()

        app.terminate()
        app.launchArguments = ["--ui-testing", "--simulate-restore-failure"]
        app.launch()
        app.descendants(matching: .any)["trash.sidebar"].click()
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.restore"].click()
        status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.label.contains("Nothing was restored"))
        XCTAssertTrue(app.staticTexts["First recoverable Thought"].exists)
        XCTAssertTrue(app.staticTexts["Second recoverable Thought"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing", "--simulate-permanent-delete-failure"]
        app.launch()
        app.descendants(matching: .any)["trash.sidebar"].click()
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.delete"].click()
        app.buttons["trash.delete.confirm"].click()
        status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.label.contains("They remain in Trash"))
        XCTAssertTrue(app.staticTexts["First recoverable Thought"].exists)
        XCTAssertTrue(app.staticTexts["Second recoverable Thought"].exists)
    }

    func testPortableExportCreatesExternalArtifactAndExcludesTrashUntilSelected() throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxRealExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let app = try launch(reset: true)
        createProject("Work/Personal", in: app)
        capture("# Project Export\n\nCanonical **project** source", destination: "Work/Personal", in: app)
        capture("Inbox export source", in: app)
        capture("Selected Trash export source", in: app)
        app.staticTexts["All Thoughts"].firstMatch.click()
        thoughtRow("Selected Trash export source", in: app).click()
        app.buttons["trash.move"].click()

        export("Export All…", in: app)
        try chooseExportDestination(destination, in: app)
        let status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(waitForLabel(status, containing: "Exported 2 Thoughts"))

        let inboxFiles = try markdownFiles(in: destination.appending(path: "Inbox", directoryHint: .isDirectory))
        let projectFiles = try markdownFiles(in: destination.appending(path: "Work-Personal", directoryHint: .isDirectory))
        XCTAssertEqual(inboxFiles.count, 1)
        XCTAssertEqual(projectFiles.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appending(path: "Trash").path))
        let projectArtifact = try String(contentsOf: projectFiles[0], encoding: .utf8)
        XCTAssertTrue(projectArtifact.contains("id: \""))
        XCTAssertTrue(projectArtifact.contains("created_at: \""))
        XCTAssertTrue(projectArtifact.contains("edited_at: \""))
        XCTAssertTrue(projectArtifact.hasSuffix("# Project Export\n\nCanonical **project** source"))

        app.descendants(matching: .any)["trash.sidebar"].click()
        thoughtRow("Selected Trash export source", in: app).click()
        app.buttons["export.selected.trash.button"].click()
        try chooseExportDestination(destination, in: app)
        XCTAssertTrue(waitForLabel(status, containing: "Exported 1 Thought"))
        let trashFiles = try markdownFiles(in: destination.appending(path: "Trash", directoryHint: .isDirectory))
        XCTAssertEqual(trashFiles.count, 1)
        XCTAssertTrue(try String(contentsOf: trashFiles[0], encoding: .utf8).hasSuffix("Selected Trash export source"))
    }

    func testExportMenuUsesItsCommandNameAndRemainsKeyboardReachable() throws {
        let app = try launch(reset: true)
        capture("Keyboard export source", in: app)

        let menu = app.descendants(matching: .any)["export.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        XCTAssertEqual(menu.label, "Export")
        XCTAssertFalse(accessibilityText(of: menu).contains("Share"))
        XCTAssertTrue(menu.isHittable)

        menu.click()
        let exportAll = app.menuItems["Export All…"]
        XCTAssertTrue(exportAll.waitForExistence(timeout: 3))
        XCTAssertTrue(exportAll.isEnabled)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.typeKey("e", modifierFlags: [.command, .shift])
        let cancel = app.buttons["CancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
    }

    func testNativeExportPickerCancellationAndWriteFailureAreAccessible() throws {
        var app = try launch(reset: true)
        capture("Cancel export", in: app)
        export("Export All…", in: app)
        let cancel = app.buttons["CancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        var status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(waitForLabel(status, containing: "No files were written"))

        app.terminate()
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxRealExportFailure-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        app = try launch(
            reset: true,
            additionalArguments: ["--simulate-export-write-failure"]
        )
        capture("Failed export", in: app)
        export("Export All…", in: app)
        try chooseExportDestination(destination, in: app)
        status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(waitForLabel(status, containing: "Could not write"))
        XCTAssertTrue(status.label.contains("Exported 0 of 1 Thought"))
        XCTAssertTrue(try markdownFilesRecursively(in: destination).isEmpty)
    }

    private func application() throws -> XCUIApplication {
        if let path = ProcessInfo.processInfo.environment["THOUGHTBOX_APP_PATH"],
           path.hasPrefix("/"),
           path.hasSuffix(".app")
        {
            return XCUIApplication(url: URL(fileURLWithPath: path, isDirectory: true))
        }
        return XCUIApplication()
    }

    private func launch(
        reset: Bool,
        simulateSaveFailure: Bool = false,
        simulateBulkMoveFailure: Bool = false,
        additionalArguments: [String] = []
    ) throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["THOUGHTBOX_RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Run this file from the Xcode Thoughtbox UI-test scheme.")
        }

        let app = try application()
        app.launchEnvironment["THOUGHTBOX_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]
        if reset { app.launchArguments.append("--reset-ui-test-store") }
        if simulateSaveFailure { app.launchArguments.append("--simulate-save-failure") }
        if simulateBulkMoveFailure { app.launchArguments.append("--simulate-bulk-move-failure") }
        app.launchArguments.append(contentsOf: additionalArguments)
        app.launch()
        return app
    }

    private func openCapture(in app: XCUIApplication) -> XCUIElement {
        app.typeKey("n", modifierFlags: .command)
        let editor = app.textViews["capture.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        return editor
    }

    private func openSettings(in app: XCUIApplication) -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let recorder = app.buttons["settings.shortcut.recorder"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 3))
        return recorder
    }

    private func capture(_ markdown: String, in app: XCUIApplication) {
        capture(markdown, destination: nil, in: app)
    }

    private func capture(_ markdown: String, destination: String?, in app: XCUIApplication) {
        let editor = openCapture(in: app)
        if let destination {
            choose(destination, from: "capture.destination", in: app)
        }
        editor.typeText(markdown)
        app.buttons["capture.save"].click()
        XCTAssertFalse(editor.exists)
    }

    private func createProject(_ name: String, in app: XCUIApplication) {
        app.buttons["project.create"].click()
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(name)
        app.buttons["project.save"].click()
        XCTAssertTrue(
            element(labeled: name.trimmingCharacters(in: .whitespacesAndNewlines), in: app)
                .waitForExistence(timeout: 3),
            app.debugDescription
        )
    }

    private func choose(_ option: String, from pickerIdentifier: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)[pickerIdentifier]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.click()
        let item = app.menuItems[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
    }

    private func export(_ option: String, in app: XCUIApplication) {
        let menu = app.descendants(matching: .any)["export.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.click()
        let item = app.menuItems[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
    }

    private func chooseExportDestination(_ destination: URL, in app: XCUIApplication) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        app.typeKey("g", modifierFlags: [.command, .shift])
        let pathField = app.textFields.firstMatch
        XCTAssertTrue(pathField.waitForExistence(timeout: 3))
        pathField.typeText(destination.path)
        pathField.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let exportButton = app.buttons["OKButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
        exportButton.click()
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func element(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.outlines["Sidebar"].staticTexts
            .matching(NSPredicate(format: "label == %@ OR value BEGINSWITH %@", label, label))
            .firstMatch
    }

    private func accessibilityText(of element: XCUIElement) -> String {
        [element.label, element.value as? String]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func controlIsOn(_ element: XCUIElement) -> Bool {
        if let number = element.value as? NSNumber { return number.boolValue }
        return (element.value as? String) == "1"
    }

    private func thoughtRow(_ markdown: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["library.thoughts"]
            .staticTexts
            .matching(NSPredicate(format: "label == %@ OR value == %@", markdown, markdown))
            .firstMatch
    }

    private func waitForVersion(_ version: String, in appPath: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let infoURL = URL(fileURLWithPath: appPath, isDirectory: true)
            .appending(path: "Contents/Info.plist")
        repeat {
            if let data = try? Data(contentsOf: infoURL),
               let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let info = propertyList as? [String: Any],
               info["CFBundleShortVersionString"] as? String == version {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }

    private func markdownFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func markdownFilesRecursively(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "md" }
    }

}
