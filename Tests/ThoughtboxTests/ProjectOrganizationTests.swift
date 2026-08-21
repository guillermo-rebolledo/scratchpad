import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct ProjectOrganizationTests {
    @Test("Project names are trimmed and unique without regard to case")
    func normalizedProjectNames() throws {
        let repository = try ThoughtRepository.inMemory()

        let project = try repository.createProject(name: "  Client Work \n")
        #expect(project.name == "Client Work")
        #expect(throws: ProjectError.duplicateName("client work")) {
            try repository.createProject(name: "client work")
        }
        #expect(throws: ProjectError.emptyName) {
            try repository.createProject(name: " \n\t")
        }
    }

    @Test("Projects stay newest-first when renamed")
    func projectOrderingDoesNotUseRenameTime() throws {
        let repository = try ThoughtRepository.inMemory()
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = olderDate.addingTimeInterval(60)
        let older = try repository.createProject(name: "Older", at: olderDate)
        let newer = try repository.createProject(name: "Newer", at: newerDate)

        try repository.renameProject(older, to: "Renamed")

        #expect(try repository.allProjects().map(\.id) == [newer.id, older.id])
        #expect(older.createdAt == olderDate)
        #expect(older.name == "Renamed")
    }

    @Test("A Thought has exactly one Project or belongs to Inbox")
    func captureAndReassignment() throws {
        let repository = try ThoughtRepository.inMemory()
        let first = try repository.createProject(name: "First")
        let second = try repository.createProject(name: "Second")
        let thought = try repository.capture(markdown: "Organize me", project: first)

        #expect(thought.project?.id == first.id)
        #expect(try repository.thoughts(in: first).map(\.id) == [thought.id])
        #expect(try repository.inboxThoughts().isEmpty)

        try repository.move(thought, to: second)
        #expect(thought.project?.id == second.id)
        #expect(try repository.thoughts(in: first).isEmpty)

        try repository.move(thought, to: nil)
        #expect(thought.project == nil)
        #expect(try repository.inboxThoughts().map(\.id) == [thought.id])
    }

    @Test("Draft destination survives recreation and resets only after successful capture")
    func draftDestinationLifecycle() throws {
        let suiteName = "ThoughtboxTests.ProjectDraft.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let projectID = UUID()

        var draft = DraftStore(defaults: defaults)
        draft.markdown = "Project-bound Draft"
        draft.projectID = projectID
        draft = DraftStore(defaults: defaults)
        #expect(draft.projectID == projectID)

        let failed = CaptureService(draft: draft) { _, _ in throw CaptureError.couldNotSave }
        #expect(throws: CaptureError.couldNotSave) { try failed.save() }
        #expect(draft.projectID == projectID)

        var capturedProjectID: UUID?
        let successful = CaptureService(draft: draft) { _, destination in
            capturedProjectID = destination
        }
        try successful.save()
        #expect(capturedProjectID == projectID)
        #expect(draft.markdown.isEmpty)
        #expect(draft.projectID == nil)
    }
}
