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

        #expect(repository.allThoughts().map(\.id) == [newer.id, older.id])
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
        #expect(repository.allThoughts().map(\.markdown) == ["Keep me safe"])

        draft.markdown = "Still here after failure"
        let failedCapture = CaptureService(draft: draft) { _ in
            throw CaptureError.couldNotSave
        }

        #expect(throws: CaptureError.couldNotSave) {
            try failedCapture.save()
        }
        #expect(draft.markdown == "Still here after failure")
    }
}
