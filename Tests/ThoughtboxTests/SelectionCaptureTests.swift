import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct SelectionCaptureTests {
    @Test("Capture Selection adds provider text and presents the persistent Draft")
    func successfulCaptureSelection() async throws {
        let defaults = try #require(UserDefaults(suiteName: "ThoughtboxSelectionCoordinator-\(UUID().uuidString)"))
        let draft = DraftStore(defaults: defaults)
        let projectID = UUID()
        draft.markdown = "Context"
        draft.projectID = projectID
        let provider = TestSelectionProvider(result: .success("  selected text  "))
        var presented = false
        var failure: SelectionCaptureError?
        let coordinator = SelectionCaptureCoordinator(
            draft: draft,
            provider: provider,
            onSuccess: { presented = true },
            onFailure: { failure = $0 }
        )

        await coordinator.captureSelection()

        #expect(draft.markdown == "Context\n\nselected text")
        #expect(draft.projectID == projectID)
        #expect(presented)
        #expect(failure == nil)
    }

    @Test("Capture Selection failures preserve the Draft and report one typed outcome")
    func failedCaptureSelection() async throws {
        let defaults = try #require(UserDefaults(suiteName: "ThoughtboxSelectionFailure-\(UUID().uuidString)"))
        let draft = DraftStore(defaults: defaults)
        draft.markdown = "Untouched"
        let provider = TestSelectionProvider(result: .failure(.unavailable))
        var presentationCount = 0
        var failures: [SelectionCaptureError] = []
        let coordinator = SelectionCaptureCoordinator(
            draft: draft,
            provider: provider,
            onSuccess: { presentationCount += 1 },
            onFailure: { failures.append($0) }
        )

        await coordinator.captureSelection()

        #expect(draft.markdown == "Untouched")
        #expect(presentationCount == 0)
        #expect(failures == [.unavailable])
    }
}

@MainActor
private final class TestSelectionProvider: SelectionProviding {
    let result: Result<String, SelectionCaptureError>

    init(result: Result<String, SelectionCaptureError>) {
        self.result = result
    }

    func selectedText() async throws -> String {
        try result.get()
    }

    func accessibilityPermissionStatus(prompt: Bool) async -> Bool {
        true
    }
}
