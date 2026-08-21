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

    func testShortcutSettingsRejectConflictActivatePersistAndRestore() throws {
        let app = try launch(reset: true, additionalArguments: ["--simulate-shortcut-conflict"])
        var recorder = openSettings(in: app)
        XCTAssertEqual(recorder.value as? String, "Control–Option–Space")

        app.typeKey(XCUIKeyboardKey.space.rawValue, modifierFlags: [])
        app.typeKey("k", modifierFlags: [.control, .option])
        let conflict = app.descendants(matching: .any)["settings.shortcut.error"]
        XCTAssertTrue(conflict.waitForExistence(timeout: 3))
        XCTAssertTrue(conflict.label.contains("previous shortcut is still active"))
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
        var toggle = app.checkBoxes["settings.login.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? Int, 0)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        _ = openSettings(in: app)
        toggle = app.checkBoxes["settings.login.toggle"]
        XCTAssertEqual(toggle.value as? Int, 1)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 0)

        app.terminate()
        app = try launch(reset: true, additionalArguments: ["--simulate-login-item-failure"])
        _ = openSettings(in: app)
        toggle = app.checkBoxes["settings.login.toggle"]
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 0)
        let error = app.descendants(matching: .any)["settings.login.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue(error.label.contains("system setting was not changed"))
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
        let app = try launch(reset: true)
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

        XCTAssertTrue(app.descendants(matching: .any)["thought.rendered"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Rendered heading"].exists)
        XCTAssertTrue(app.staticTexts["Image not loaded: private"].exists)
        XCTAssertFalse(app.images["private"].exists)
        XCTAssertFalse(app.staticTexts["https://tracker.example/pixel.png"].exists)
        let externalLink = app.links["Example"]
        XCTAssertTrue(externalLink.isEnabled)
        externalLink.click()
        let browserOpened = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "state == %d", XCUIApplication.State.runningBackground.rawValue),
            object: app
        )
        wait(for: [browserOpened], timeout: 3)
        app.activate()
        XCTAssertTrue(app.staticTexts["Table with 2 columns and 1 rows"].exists || app.staticTexts["Name"].exists)
    }

    func testEditAutoSavesAndSurvivesRelaunch() throws {
        let app = try launch(reset: true)
        capture("Before edit", in: app)

        app.radioButtons["Edit"].click()
        let editor = app.textViews["thought.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("After edit")
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 3))
        app.radioButtons["Read"].click()
        XCTAssertTrue(app.staticTexts["After edit"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["After edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Edited '")).firstMatch.exists)
    }

    func testEditingOlderThoughtDoesNotChangeCreationOrder() throws {
        let app = try launch(reset: true)
        capture("Older Thought", in: app)
        capture("Newer Thought", in: app)

        let newerRow = app.staticTexts["Newer Thought"]
        let olderRow = app.staticTexts["Older Thought"]
        XCTAssertLessThan(newerRow.frame.minY, olderRow.frame.minY)
        olderRow.click()
        app.radioButtons["Edit"].click()
        let editor = app.textViews["thought.editor"]
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Older Thought edited")
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 3))

        XCTAssertLessThan(newerRow.frame.minY, app.staticTexts["Older Thought edited"].frame.minY)
    }

    func testEditSavesImmediatelyOnFocusAndThoughtSelectionChanges() throws {
        let app = try launch(reset: true)
        capture("First Thought", in: app)
        capture("Second Thought", in: app)

        app.staticTexts["First Thought"].click()
        app.radioButtons["Edit"].click()
        var editor = app.textViews["thought.editor"]
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Saved by selection")
        app.staticTexts["Second Thought"].click()
        app.staticTexts["Saved by selection"].click()
        XCTAssertTrue(app.staticTexts["Saved by selection"].exists)

        app.radioButtons["Edit"].click()
        editor = app.textViews["thought.editor"]
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Saved by focus")
        app.radioButtons["Read"].click()
        XCTAssertTrue(app.staticTexts["Saved by focus"].waitForExistence(timeout: 3))
    }

    func testProjectCreationNormalizedUniquenessOrderingAndRename() throws {
        let app = try launch(reset: true)
        createProject("  Older Project  ", in: app)
        createProject("Newer Project", in: app)

        let newer = app.staticTexts["Newer Project"].firstMatch
        let older = app.staticTexts["Older Project"].firstMatch
        XCTAssertTrue(newer.exists)
        XCTAssertTrue(older.exists)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY)

        app.buttons["project.create"].click()
        let name = app.textFields["project.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("older project")
        app.buttons["project.save"].click()
        let duplicateError = app.descendants(matching: .any)["project.error"]
        XCTAssertTrue(duplicateError.waitForExistence(timeout: 3))
        XCTAssertTrue(duplicateError.label.contains("without regard to capitalization"))
        app.buttons["Cancel"].click()

        older.click()
        app.buttons["project.rename"].click()
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Renamed Project")
        app.buttons["project.save"].click()

        let renamed = app.staticTexts["Renamed Project"].firstMatch
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
        XCTAssertGreaterThan(app.staticTexts.matching(NSPredicate(format: "label == 'Inbox'")).count, 1)
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

        search.typeKey("a", modifierFlags: .command)
        search.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Project other content"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Search Project"].firstMatch.isSelected)

        search.typeText("No matching Thought")
        XCTAssertTrue(app.staticTexts["No Search Results"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(selectionCount.label.contains("2 Thoughts selected"))

        app.typeKey("m", modifierFlags: [.command, .shift])
        let inboxDestination = app.menuItems["Inbox"]
        XCTAssertTrue(inboxDestination.waitForExistence(timeout: 3))
        inboxDestination.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["bulk.status"].waitForExistence(timeout: 3))

        app.staticTexts["Inbox"].firstMatch.click()
        let newer = app.staticTexts["Newer Bulk Thought"]
        let older = app.staticTexts["Older Bulk Thought"]
        XCTAssertTrue(newer.exists)
        XCTAssertTrue(older.exists)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Newer Bulk Thought"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Older Bulk Thought"].exists)
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
        XCTAssertTrue(selectionCount.label.contains("2 Thoughts selected"))
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
        app.staticTexts["Oldest Trash Thought"].click()
        app.buttons["trash.move"].click()
        XCTAssertTrue(app.descendants(matching: .any)["bulk.status"].label.contains("Moved 1 Thought"))

        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["bulk.selection.count"].label.contains("2 Thoughts selected"))
        app.buttons["trash.move"].click()

        app.descendants(matching: .any)["trash.sidebar"].click()
        let newest = app.staticTexts["Newest Trash SearchNeedle"]
        let middle = app.staticTexts["Middle Trash Thought"]
        let oldest = app.staticTexts["Oldest Trash Thought"]
        XCTAssertTrue(newest.waitForExistence(timeout: 3))
        XCTAssertLessThan(newest.frame.minY, middle.frame.minY)
        XCTAssertLessThan(middle.frame.minY, oldest.frame.minY)

        let search = app.searchFields.firstMatch
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
        XCTAssertTrue(newest.waitForExistence(timeout: 3))
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.buttons["trash.restore"].click()

        app.staticTexts["Trash Source"].firstMatch.click()
        XCTAssertTrue(newest.waitForExistence(timeout: 3))
        XCTAssertTrue(middle.exists)
        XCTAssertTrue(oldest.exists)
    }

    func testProjectDeleteConstraintDraftFallbackRestoreFallbackAndPermanentDelete() throws {
        let app = try launch(reset: true)
        createProject("Disposable Project", in: app)
        capture("Disposable Thought", destination: "Disposable Project", in: app)

        app.staticTexts["Disposable Project"].firstMatch.click()
        app.buttons["project.delete"].click()
        let status = app.descendants(matching: .any)["bulk.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.label.contains("Move or delete it before deleting the Project"))

        let editor = openCapture(in: app)
        choose("Disposable Project", from: "capture.destination", in: app)
        editor.typeText("Draft remains intact")
        editor.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.staticTexts["Disposable Thought"].click()
        app.buttons["trash.move"].click()
        app.buttons["project.delete"].click()
        XCTAssertTrue(app.buttons["project.delete.confirm"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'formerly belonged'")).firstMatch.exists)
        app.buttons["project.delete.confirm"].click()
        XCTAssertFalse(app.staticTexts["Disposable Project"].firstMatch.exists)
        XCTAssertTrue(status.label.contains("Draft is intact"))

        let restoredDraft = openCapture(in: app)
        XCTAssertEqual(restoredDraft.value as? String, "Draft remains intact")
        XCTAssertEqual(app.descendants(matching: .any)["capture.destination"].value as? String, "Inbox")
        XCTAssertTrue(app.descendants(matching: .any)["capture.destination.notice"].exists)
        restoredDraft.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.descendants(matching: .any)["trash.sidebar"].click()
        app.staticTexts["Disposable Thought"].click()
        app.buttons["trash.restore"].click()
        app.staticTexts["Inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Disposable Thought"].waitForExistence(timeout: 3))

        app.buttons["trash.move"].click()
        app.descendants(matching: .any)["trash.sidebar"].click()
        app.staticTexts["Disposable Thought"].click()
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
        app.staticTexts["Selected Trash export source"].click()
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
        app.staticTexts["Selected Trash export source"].click()
        app.buttons["export.selected.trash.button"].click()
        try chooseExportDestination(destination, in: app)
        XCTAssertTrue(waitForLabel(status, containing: "Exported 1 Thought"))
        let trashFiles = try markdownFiles(in: destination.appending(path: "Trash", directoryHint: .isDirectory))
        XCTAssertEqual(trashFiles.count, 1)
        XCTAssertTrue(try String(contentsOf: trashFiles[0], encoding: .utf8).hasSuffix("Selected Trash export source"))
    }

    func testNativeExportPickerCancellationAndWriteFailureAreAccessible() throws {
        var app = try launch(reset: true)
        capture("Cancel export", in: app)
        export("Export All…", in: app)
        let cancel = app.buttons["Cancel"]
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
        if let path = ProcessInfo.processInfo.environment["THOUGHTBOX_APP_PATH"] {
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
        XCTAssertTrue(app.staticTexts[name.trimmingCharacters(in: .whitespacesAndNewlines)].firstMatch.waitForExistence(timeout: 3))
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
        let exportButton = app.buttons["Export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
        exportButton.click()
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
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
