import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct TrashLifecycleTests {
    @Test("Trashing is atomic, clears the active Project, and retains restoration identity")
    func trashLifecycle() throws {
        struct SimulatedFailure: Error {}

        let repository = try ThoughtRepository.inMemory()
        let project = try repository.createProject(name: "Archive source")
        let older = try repository.capture(
            markdown: "Older",
            at: Date(timeIntervalSince1970: 1_700_000_000),
            project: project
        )
        let newer = try repository.capture(
            markdown: "Newer",
            at: Date(timeIntervalSince1970: 1_700_000_060),
            project: project
        )

        #expect(throws: SimulatedFailure.self) {
            try repository.trash([older, newer], at: .now) { throw SimulatedFailure() }
        }
        #expect(older.trashedAt == nil)
        #expect(older.project?.id == project.id)
        #expect(newer.trashedAt == nil)
        #expect(newer.project?.id == project.id)

        let trashedAt = Date(timeIntervalSince1970: 1_700_000_120)
        #expect(try repository.trash([older, newer], at: trashedAt) == 2)
        #expect(older.trashedAt == trashedAt)
        #expect(older.project == nil)
        #expect(older.formerProjectID == project.id)
        #expect(newer.project == nil)
        #expect(newer.formerProjectID == project.id)
        #expect(try repository.allThoughts().isEmpty)
        #expect(try repository.trashedThoughts().map(\.id) == [newer.id, older.id])

        let reopenedRepository = ThoughtRepository(container: repository.container)
        #expect(try reopenedRepository.trashedThoughts().map(\.id) == [newer.id, older.id])
    }

    @Test("Bulk restore returns Thoughts to an existing Project or falls back to Inbox")
    func restoreDestinations() throws {
        let repository = try ThoughtRepository.inMemory()
        let retainedProject = try repository.createProject(name: "Retained")
        let deletedProject = try repository.createProject(name: "Deleted")
        let retained = try repository.capture(markdown: "Retained destination", project: retainedProject)
        let fallback = try repository.capture(markdown: "Fallback destination", project: deletedProject)
        let inbox = try repository.capture(markdown: "Inbox destination")
        try repository.trash([retained, fallback, inbox])

        _ = try repository.deleteProject(deletedProject, draft: nil)
        let result = try repository.restore([retained, fallback, inbox])

        #expect(result.restoredCount == 3)
        #expect(result.inboxFallbackCount == 1)
        #expect(retained.project?.id == retainedProject.id)
        #expect(fallback.project == nil)
        #expect(inbox.project == nil)
        #expect([retained, fallback, inbox].allSatisfy { $0.trashedAt == nil && $0.formerProjectID == nil })
    }

    @Test("Bulk restore rolls every Thought back when its single save fails")
    func atomicRestoreFailure() throws {
        struct SimulatedFailure: Error {}

        let repository = try ThoughtRepository.inMemory()
        let project = try repository.createProject(name: "Restore")
        let first = try repository.capture(markdown: "First", project: project)
        let second = try repository.capture(markdown: "Second", project: project)
        try repository.trash([first, second])
        let firstTrashedAt = first.trashedAt
        let secondTrashedAt = second.trashedAt

        #expect(throws: SimulatedFailure.self) {
            try repository.restore([first, second]) { throw SimulatedFailure() }
        }
        #expect(first.trashedAt == firstTrashedAt)
        #expect(second.trashedAt == secondTrashedAt)
        #expect(first.project == nil)
        #expect(second.project == nil)
        #expect(first.formerProjectID == project.id)
        #expect(second.formerProjectID == project.id)
    }

    @Test("Permanent deletion accepts only Trash and remains recoverable on save failure")
    func permanentDeletionSafety() throws {
        struct SimulatedFailure: Error {}

        let repository = try ThoughtRepository.inMemory()
        let active = try repository.capture(markdown: "Active")
        let trashed = try repository.capture(markdown: "Trashed")
        let secondTrashed = try repository.capture(markdown: "Second trashed")
        try repository.trash([trashed, secondTrashed])

        #expect(throws: TrashError.onlyTrashCanBePermanentlyDeleted(count: 1)) {
            try repository.permanentlyDelete([active, trashed])
        }
        #expect(try repository.trashedThoughts().map(\.id) == [secondTrashed.id, trashed.id])

        active.markdown = "Unrelated pending edit"
        #expect(throws: SimulatedFailure.self) {
            try repository.permanentlyDelete([trashed, secondTrashed]) { throw SimulatedFailure() }
        }
        #expect(try repository.trashedThoughts().map(\.id) == [secondTrashed.id, trashed.id])
        #expect(active.markdown == "Unrelated pending edit")

        #expect(try repository.permanentlyDelete([trashed, secondTrashed]) == 2)
        #expect(try repository.trashedThoughts().isEmpty)
        #expect(try repository.allThoughts().map(\.id) == [active.id])
    }

    @Test("Project deletion blocks active content, warns about Trash, and preserves Draft Markdown")
    func safeProjectDeletionAndDraftFallback() throws {
        struct SimulatedFailure: Error {}

        let suiteName = "TrashLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let draft = DraftStore(defaults: defaults)
        let repository = try ThoughtRepository.inMemory()
        let project = try repository.createProject(name: "Disposable")
        let retainedProject = try repository.createProject(name: "Retained")
        let thought = try repository.capture(markdown: "Former project Thought", project: project)
        draft.markdown = "Draft must survive"
        draft.projectID = project.id

        #expect(try repository.projectDeletionImpact(for: project) == .init(activeThoughtCount: 1, trashedThoughtCount: 0))
        #expect(throws: TrashError.projectContainsActiveThoughts(count: 1)) {
            try repository.deleteProject(project, draft: draft)
        }
        #expect(draft.markdown == "Draft must survive")
        #expect(draft.projectID == project.id)

        try repository.trash(thought)
        retainedProject.name = "Unrelated pending rename"
        #expect(try repository.projectDeletionImpact(for: project) == .init(activeThoughtCount: 0, trashedThoughtCount: 1))
        #expect(throws: SimulatedFailure.self) {
            try repository.deleteProject(project, draft: draft) { throw SimulatedFailure() }
        }
        #expect(try repository.allProjects().contains { $0.id == project.id })
        #expect(draft.markdown == "Draft must survive")
        #expect(draft.projectID == project.id)
        #expect(retainedProject.name == "Unrelated pending rename")

        let result = try repository.deleteProject(project, draft: draft)
        #expect(result.trashedThoughtCount == 1)
        #expect(result.draftDestinationReset)
        #expect(draft.markdown == "Draft must survive")
        #expect(draft.projectID == nil)

        let restoreResult = try repository.restore(thought)
        #expect(restoreResult.inboxFallbackCount == 1)
        #expect(thought.project == nil)
    }
}
