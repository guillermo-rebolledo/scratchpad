import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct SearchOrganizationTests {
    @Test("Search uses full rendered text while preserving newest-first scope order")
    func searchablePlainTextAndOrdering() throws {
        let repository = try ThoughtRepository.inMemory()
        let project = try repository.createProject(name: "Research")
        let older = try repository.capture(
            markdown: "# Alpha\n\nA [linked phrase](https://example.com)",
            at: Date(timeIntervalSince1970: 1_700_000_000),
            project: project
        )
        let newer = try repository.capture(
            markdown: "```swift\nlet SearchNeedle = true\n```",
            at: Date(timeIntervalSince1970: 1_700_000_060),
            project: project
        )
        _ = try repository.capture(markdown: "Inbox SearchNeedle")

        let projectResults = ThoughtSearch.filter(try repository.thoughts(in: project), query: "searchneedle")
        #expect(projectResults.map(\.id) == [newer.id])
        #expect(ThoughtSearch.filter(try repository.thoughts(in: project), query: "linked phrase").map(\.id) == [older.id])
        #expect(ThoughtSearch.filter(try repository.allThoughts(), query: "searchneedle").count == 2)
        let allThoughts = try repository.allThoughts()
        #expect(ThoughtSearch.filter(allThoughts, query: "").map(\.id) == allThoughts.map(\.id))

        try repository.update(older, markdown: "Updated searchable phrase")
        #expect(ThoughtSearch.filter(try repository.allThoughts(), query: "linked phrase").isEmpty)
        #expect(ThoughtSearch.filter(try repository.allThoughts(), query: "updated searchable").map(\.id) == [older.id])
    }

    @Test("Active scopes exclude trashed Thoughts")
    func activeScopesExcludeTrash() throws {
        let repository = try ThoughtRepository.inMemory()
        let project = try repository.createProject(name: "Active")
        let inbox = try repository.capture(markdown: "Inbox active")
        let projectThought = try repository.capture(markdown: "Project active", project: project)
        let trashed = try repository.capture(markdown: "Deleted SearchNeedle", project: project)
        trashed.trashedAt = .now

        #expect(try repository.allThoughts().map(\.id).contains(trashed.id) == false)
        #expect(try repository.inboxThoughts().map(\.id) == [inbox.id])
        #expect(try repository.thoughts(in: project).map(\.id) == [projectThought.id])
        #expect(ThoughtSearch.filter(try repository.allThoughts(), query: "SearchNeedle").isEmpty)
    }

    @Test("Bulk movement is one atomic save and preserves Thought identity, content, and creation order")
    func atomicBulkMovement() throws {
        struct SimulatedFailure: Error {}

        let repository = try ThoughtRepository.inMemory()
        let source = try repository.createProject(name: "Source")
        let destination = try repository.createProject(name: "Destination")
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = olderDate.addingTimeInterval(60)
        let older = try repository.capture(markdown: "Duplicate", at: olderDate, project: source)
        let newer = try repository.capture(markdown: "Duplicate", at: newerDate, project: source)

        #expect(throws: SimulatedFailure.self) {
            try repository.move([newer, older], to: destination) { throw SimulatedFailure() }
        }
        #expect(newer.project?.id == source.id)
        #expect(older.project?.id == source.id)

        let changedCount = try repository.move([newer, older], to: destination)
        #expect(changedCount == 2)
        #expect(try repository.move([newer, older], to: destination) == 0)
        let moved = try repository.thoughts(in: destination)
        #expect(moved.map(\.id) == [newer.id, older.id])
        #expect(moved.map(\.markdown) == ["Duplicate", "Duplicate"])
        #expect(moved.map(\.createdAt) == [newerDate, olderDate])
    }

    @Test("A large active library remains searchable without losing order")
    func largeLibrarySearch() {
        let count = 500
        let thoughts = (0..<count).map { index in
            Thought(
                markdown: index.isMultiple(of: 199) ? "Scale SearchNeedle \(index)" : "Scale Thought \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }.reversed()

        let matches = ThoughtSearch.filter(Array(thoughts), query: "searchneedle")

        #expect(matches.count == 3)
        #expect(matches.map(\.createdAt) == matches.map(\.createdAt).sorted(by: >))
        #expect(matches.first?.markdown == "Scale SearchNeedle 398")
        #expect(matches.last?.markdown == "Scale SearchNeedle 0")
    }
}
