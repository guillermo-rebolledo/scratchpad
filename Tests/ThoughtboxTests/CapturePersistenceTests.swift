import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct CapturePersistenceTests {
    @Test("Draft survives recreation and remains singular")
    func draftSurvivesRecreation() throws {
        let suiteName = "ThoughtboxTests.Draft.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = DraftStore(defaults: defaults)
        first.markdown = "A **durable** idea"

        let restored = DraftStore(defaults: defaults)
        #expect(restored.markdown == "A **durable** idea")

        restored.clear()
        #expect(DraftStore(defaults: defaults).markdown.isEmpty)
    }

    @Test("Preparing capture for a collection preserves Draft Markdown and persists its destination")
    func preparingCollectionCapturePreservesDraft() throws {
        let suiteName = "ThoughtboxTests.EmptyCollectionDraft.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let projectID = UUID()
        let draft = DraftStore(defaults: defaults)
        draft.markdown = "Keep this Draft"

        draft.prepareForCapture(in: projectID)

        #expect(draft.markdown == "Keep this Draft")
        #expect(DraftStore(defaults: defaults).projectID == projectID)
    }

    @Test("Selected text is normalized and appended without changing the Draft destination")
    func selectedTextAppendsToDraft() throws {
        let suiteName = "ThoughtboxTests.SelectionDraft.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let projectID = UUID()
        let draft = DraftStore(defaults: defaults)
        draft.markdown = "Existing **context**"
        draft.projectID = projectID

        try draft.addSelectedText("  First line\n\nSecond line  \n")

        #expect(draft.markdown == "Existing **context**\n\nFirst line\n\nSecond line")
        #expect(draft.projectID == projectID)
        #expect(DraftStore(defaults: defaults).markdown == draft.markdown)
    }

    @Test("Selected text rejects empty and oversized results atomically")
    func selectedTextValidationIsAtomic() throws {
        let suiteName = "ThoughtboxTests.SelectionLimit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let draft = DraftStore(defaults: defaults)
        draft.markdown = "Keep"

        #expect(throws: SelectionCaptureError.noSelection) {
            try draft.addSelectedText(" \n\t ")
        }
        #expect(draft.markdown == "Keep")

        let availableCharacters = DraftStore.maximumSelectionDraftCharacters - "Keep\n\n".count
        try draft.addSelectedText(String(repeating: "a", count: availableCharacters))
        #expect(draft.markdown.count == DraftStore.maximumSelectionDraftCharacters)

        #expect(throws: SelectionCaptureError.tooLarge) {
            try draft.addSelectedText("b")
        }
        #expect(draft.markdown.count == DraftStore.maximumSelectionDraftCharacters)
    }

    @Test("Capture rejects blank input and returns newest Thoughts first")
    func captureValidationAndOrdering() throws {
        let repository = try ThoughtRepository.inMemory()

        #expect(throws: CaptureError.emptyThought) {
            try repository.capture(markdown: "  \n\t")
        }

        let olderDate = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 10))
        )
        let newerDate = olderDate.addingTimeInterval(60)
        let older = try repository.capture(markdown: "First", at: olderDate)
        let newer = try repository.capture(markdown: "Second", at: newerDate)

        #expect(try repository.allThoughts().map(\.id) == [newer.id, older.id])
        #expect(older.markdown == "First")
        #expect(older.createdAt == older.editedAt)
    }

    @Test("Capture clears the Draft only after a successful durable save")
    func captureClearsDraftOnlyOnSuccess() throws {
        let suiteName = "ThoughtboxTests.Capture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let draft = DraftStore(defaults: defaults)
        draft.markdown = "Keep me safe"
        let repository = try ThoughtRepository.inMemory()
        let successfulCapture = CaptureService(draft: draft) { markdown in
            try repository.capture(markdown: markdown)
        }

        try successfulCapture.save()
        #expect(draft.markdown.isEmpty)
        #expect(try repository.allThoughts().map(\.markdown) == ["Keep me safe"])

        draft.markdown = "Still here after failure"
        let failedCapture = CaptureService(draft: draft) { _ in
            throw CaptureError.couldNotSave
        }

        #expect(throws: CaptureError.couldNotSave) {
            try failedCapture.save()
        }
        #expect(draft.markdown == "Still here after failure")
    }

    @Test("A failed repository capture removes its pending insertion before retry")
    func failedCaptureDoesNotPersistLater() throws {
        struct SimulatedFailure: Error {}

        let repository = try ThoughtRepository.inMemory()
        #expect(throws: SimulatedFailure.self) {
            try repository.capture(
                markdown: "Failed once",
                saveChanges: { throw SimulatedFailure() }
            )
        }

        _ = try repository.capture(markdown: "Successful retry")
        #expect(try repository.allThoughts().map(\.markdown) == ["Successful retry"])
    }
}
