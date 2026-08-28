import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct MenuBarThoughtTests {
    @Test("The selected Thought and source persist until another Thought is selected")
    func selectionPersistsAndAdvances() throws {
        let suiteName = "MenuBarThoughtSelectionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let project = Project(name: "Work")
        let newest = Thought(markdown: "Newest", createdAt: Date(timeIntervalSince1970: 2), project: project)
        let older = Thought(markdown: "Older", createdAt: Date(timeIntervalSince1970: 1), project: project)
        let inbox = Thought(markdown: "Inbox", createdAt: Date(timeIntervalSince1970: 0))
        let thoughts = [newest, older, inbox]
        let projectIDs: Set<UUID> = [project.id]
        let selection = MenuBarThoughtSelection(defaults: defaults)

        #expect(selection.reconcile(thoughts: thoughts, projectIDs: projectIDs)?.id == newest.id)
        #expect(selection.selectAnother(thoughts: thoughts, projectIDs: projectIDs)?.id == older.id)

        let relaunched = MenuBarThoughtSelection(defaults: defaults)
        #expect(relaunched.reconcile(thoughts: thoughts, projectIDs: projectIDs)?.id == older.id)

        relaunched.selectScope(.inbox, thoughts: thoughts, projectIDs: projectIDs)
        #expect(relaunched.thoughtID == inbox.id)
        #expect(relaunched.scope == .inbox)
    }

    @Test("A specific Thought can be selected from the active source and persists")
    func specificThoughtSelectionPersists() throws {
        let suiteName = "MenuBarThoughtSpecificSelection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let project = Project(name: "Work")
        let first = Thought(markdown: "First", project: project)
        let selected = Thought(markdown: "Selected", project: project)
        let inbox = Thought(markdown: "Inbox")
        let thoughts = [first, selected, inbox]
        let projectIDs: Set<UUID> = [project.id]
        let selection = MenuBarThoughtSelection(defaults: defaults)
        selection.selectScope(.project(project.id), thoughts: thoughts, projectIDs: projectIDs)

        #expect(selection.selectThought(selected.id, thoughts: thoughts, projectIDs: projectIDs)?.id == selected.id)
        #expect(selection.selectThought(inbox.id, thoughts: thoughts, projectIDs: projectIDs) == nil)
        #expect(selection.thoughtID == selected.id)

        let relaunched = MenuBarThoughtSelection(defaults: defaults)
        #expect(relaunched.reconcile(thoughts: thoughts, projectIDs: projectIDs)?.id == selected.id)
    }

    @Test("A removed Project falls back to All Thoughts")
    func missingProjectFallsBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarThoughtMissingProject-\(UUID().uuidString)"))
        let selection = MenuBarThoughtSelection(defaults: defaults)
        let thought = Thought(markdown: "Available")

        selection.selectScope(.project(UUID()), thoughts: [thought], projectIDs: [])
        #expect(selection.reconcile(thoughts: [thought], projectIDs: [])?.id == thought.id)
        #expect(selection.scope == .allThoughts)
    }

    @Test("Only Projects with active Thoughts appear as menu bar sources")
    func projectSourcesExcludeEmptyAndTrashOnlyProjects() {
        let activeProject = Project(name: "Active")
        let emptyProject = Project(name: "Empty")
        let trashOnlyProject = Project(name: "Trash only")
        let activeThought = Thought(markdown: "Available", project: activeProject)
        let trashedThought = Thought(markdown: "Trashed", trashedAt: .now, project: trashOnlyProject)

        let projects = MenuBarThoughtScope.populatedProjects(
            from: [activeProject, emptyProject, trashOnlyProject],
            thoughts: [activeThought, trashedThought]
        )

        #expect(projects.map(\.id) == [activeProject.id])
    }

    @Test("A selected Project falls back to All Thoughts when it becomes empty")
    func emptyProjectFallsBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarThoughtEmptyProject-\(UUID().uuidString)"))
        let project = Project(name: "Work")
        let projectThought = Thought(markdown: "Project", project: project)
        let inboxThought = Thought(markdown: "Inbox")
        let selection = MenuBarThoughtSelection(defaults: defaults)
        selection.selectScope(.project(project.id), thoughts: [projectThought, inboxThought], projectIDs: [project.id])

        #expect(selection.reconcile(thoughts: [inboxThought], projectIDs: [project.id])?.id == inboxThought.id)
        #expect(selection.scope == .allThoughts)
    }

    @Test("A moved Thought stays selected and its source follows its new destination")
    func movedThoughtStaysSelected() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarThoughtMoved-\(UUID().uuidString)"))
        let project = Project(name: "Work")
        let thought = Thought(markdown: "Follow me", project: project)
        let selection = MenuBarThoughtSelection(defaults: defaults)
        selection.selectScope(.project(project.id), thoughts: [thought], projectIDs: [project.id])

        thought.project = nil

        #expect(selection.reconcile(thoughts: [thought], projectIDs: [project.id])?.id == thought.id)
        #expect(selection.scope == .inbox)
    }

    @Test("A moved Thought follows another Project")
    func movedThoughtFollowsAnotherProject() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarThoughtMovedProject-\(UUID().uuidString)"))
        let originalProject = Project(name: "Original")
        let destinationProject = Project(name: "Destination")
        let thought = Thought(markdown: "Follow me", project: originalProject)
        let selection = MenuBarThoughtSelection(defaults: defaults)
        let projectIDs: Set<UUID> = [originalProject.id, destinationProject.id]
        selection.selectScope(.project(originalProject.id), thoughts: [thought], projectIDs: projectIDs)

        thought.project = destinationProject

        #expect(selection.reconcile(thoughts: [thought], projectIDs: projectIDs)?.id == thought.id)
        #expect(selection.scope == .project(destinationProject.id))
    }

    @Test("A deleted selected Thought falls back to the next available Thought")
    func deletedThoughtFallsBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarThoughtDeleted-\(UUID().uuidString)"))
        let deleted = Thought(markdown: "Deleted")
        let fallback = Thought(markdown: "Fallback")
        let selection = MenuBarThoughtSelection(defaults: defaults)

        #expect(selection.reconcile(thoughts: [deleted, fallback], projectIDs: [])?.id == deleted.id)
        #expect(selection.reconcile(thoughts: [fallback], projectIDs: [])?.id == fallback.id)
        #expect(selection.thoughtID == fallback.id)
    }

    @Test("Editing replaces the complete Markdown while keeping the same Thought")
    func editThought() throws {
        let repository = try ThoughtRepository.inMemory()
        let thought = try repository.capture(markdown: "Original")
        let editedAt = Date(timeIntervalSince1970: 100)

        try MenuBarThoughtEditor.save("Rewritten\n\nwith **Markdown**", to: thought, using: repository, at: editedAt)

        #expect(thought.markdown == "Rewritten\n\nwith **Markdown**")
        #expect(thought.editedAt == editedAt)
        #expect(throws: MenuBarThoughtEditError.emptyThought) {
            try MenuBarThoughtEditor.save("  \n", to: thought, using: repository)
        }
        #expect(thought.markdown == "Rewritten\n\nwith **Markdown**")
    }

    @Test("A disappeared loaded Thought cannot redirect preserved edits to another Thought")
    func disappearedLoadedThoughtDoesNotCorruptSelection() throws {
        let repository = try ThoughtRepository.inMemory()
        let original = try repository.capture(markdown: "Original")
        let unrelated = try repository.capture(markdown: "Unrelated")

        #expect(throws: MenuBarThoughtEditError.thoughtUnavailable) {
            try MenuBarThoughtEditor.save(
                "Preserved edits",
                loadedThoughtID: original.id,
                among: [unrelated],
                using: repository
            )
        }
        #expect(original.markdown == "Original")
        #expect(unrelated.markdown == "Unrelated")

        original.trashedAt = .now
        #expect(throws: MenuBarThoughtEditError.thoughtUnavailable) {
            try MenuBarThoughtEditor.save(
                "Preserved edits",
                loadedThoughtID: original.id,
                among: [original, unrelated],
                using: repository
            )
        }
        #expect(original.markdown == "Original")
        #expect(unrelated.markdown == "Unrelated")
    }

    @Test("Editing preserves meaningful Markdown whitespace exactly")
    func editPreservesMarkdownWhitespace() throws {
        let repository = try ThoughtRepository.inMemory()
        let thought = try repository.capture(markdown: "Original")
        let edited = "  leading text\n\n    indented code  \n"

        try MenuBarThoughtEditor.save(edited, to: thought, using: repository)
        #expect(thought.markdown == edited)
    }

    @Test("Edit failures preserve the Thought and map to a retryable error")
    func editFailureIsAtomic() throws {
        let repository = try ThoughtRepository.inMemory()
        let thought = try repository.capture(markdown: "Original")
        struct SaveFailure: Error {}

        #expect(throws: MenuBarThoughtEditError.couldNotSave) {
            try MenuBarThoughtEditor.save("Retry me", to: thought, using: repository) {
                throw SaveFailure()
            }
        }
        #expect(thought.markdown == "Original")
    }

    @Test("Scopes round-trip and exclude Thoughts outside their active collection")
    func scopeFilteringAndStorage() {
        let project = Project(name: "Work")
        let projectThought = Thought(markdown: "Project", project: project)
        let inboxThought = Thought(markdown: "Inbox")
        let trashedThought = Thought(markdown: "Trash", trashedAt: .now)

        #expect(MenuBarThoughtScope(storageValue: "all") == .allThoughts)
        #expect(MenuBarThoughtScope(storageValue: "inbox") == .inbox)
        #expect(MenuBarThoughtScope(storageValue: "project:\(project.id.uuidString)") == .project(project.id))
        #expect(MenuBarThoughtScope(storageValue: "project:not-a-uuid") == nil)
        #expect(MenuBarThoughtScope.inbox.includes(inboxThought))
        #expect(!MenuBarThoughtScope.inbox.includes(projectThought))
        #expect(MenuBarThoughtScope.project(project.id).includes(projectThought))
        #expect(!MenuBarThoughtScope.allThoughts.includes(trashedThought))
    }

    @Test("Selection cycles, wraps, and handles empty and single-Thought sources")
    func selectionBoundaries() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarThoughtBoundaries-\(UUID().uuidString)"))
        let selection = MenuBarThoughtSelection(defaults: defaults)
        let first = Thought(markdown: "First")
        let second = Thought(markdown: "Second")

        #expect(selection.reconcile(thoughts: [], projectIDs: []) == nil)
        #expect(selection.thoughtID == nil)
        #expect(selection.selectAnother(thoughts: [first], projectIDs: [])?.id == first.id)
        #expect(selection.selectAnother(thoughts: [first, second], projectIDs: [])?.id == second.id)
        #expect(selection.selectAnother(thoughts: [first, second], projectIDs: [])?.id == first.id)
        #expect(selection.selectAnother(thoughts: [], projectIDs: []) == nil)
        #expect(selection.thoughtID == nil)
    }

    @Test("The menu bar shortcut is independent and persistent")
    func shortcutLifecycle() throws {
        let suiteName = "MenuBarThoughtShortcutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsModel(defaults: defaults, loginItemService: MenuBarThoughtTestLoginItemService())
        var registrations: [CaptureShortcut] = []
        model.connectMenuBarThoughtShortcutRegistration { registrations.append($0) }

        #expect(model.menuBarThoughtShortcut == .menuBarThoughtDefault)
        let replacement = CaptureShortcut(keyCode: 17, modifiers: [.command, .shift])
        model.assignMenuBarThoughtShortcut(replacement)
        #expect(model.menuBarThoughtShortcut == replacement)
        #expect(registrations == [.menuBarThoughtDefault, replacement])

        let relaunched = SettingsModel(defaults: defaults, loginItemService: MenuBarThoughtTestLoginItemService())
        #expect(relaunched.menuBarThoughtShortcut == replacement)

        relaunched.connectMenuBarThoughtShortcutRegistration { shortcut in
            if shortcut == replacement { throw GlobalShortcutError.unavailable }
        }
        #expect(relaunched.menuBarThoughtShortcutError != nil)
        relaunched.assignMenuBarThoughtShortcut(.init(keyCode: 17, modifiers: []))
        #expect(relaunched.menuBarThoughtShortcut == replacement)
        relaunched.connectMenuBarThoughtShortcutRegistration { shortcut in
            if shortcut.keyCode == 40 { throw GlobalShortcutError.unavailable }
        }
        relaunched.assignMenuBarThoughtShortcut(.init(keyCode: 40, modifiers: [.control]))
        #expect(relaunched.menuBarThoughtShortcut == replacement)
        #expect(relaunched.menuBarThoughtShortcutError != nil)
        relaunched.restoreDefaultMenuBarThoughtShortcut()
        #expect(relaunched.menuBarThoughtShortcut == .menuBarThoughtDefault)
    }

    @Test("Shortcut assignment waits until registration is connected")
    func shortcutAssignmentBeforeRegistration() throws {
        let suiteName = "MenuBarThoughtDisconnectedShortcut-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsModel(defaults: defaults, loginItemService: MenuBarThoughtTestLoginItemService())
        let candidate = CaptureShortcut(keyCode: 17, modifiers: [.command, .shift])

        model.assignMenuBarThoughtShortcut(candidate)

        #expect(model.menuBarThoughtShortcut == .menuBarThoughtDefault)
        var registered: CaptureShortcut?
        model.connectMenuBarThoughtShortcutRegistration { registered = $0 }
        #expect(registered == .menuBarThoughtDefault)
    }
}

@MainActor
private final class MenuBarThoughtTestLoginItemService: LoginItemServicing {
    var status: LoginItemStatus = .notRegistered
    func setEnabled(_ enabled: Bool) throws {
        status = enabled ? .enabled : .notRegistered
    }
}
