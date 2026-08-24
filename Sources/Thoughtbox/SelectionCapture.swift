import Foundation

@MainActor
protocol SelectionProviding: AnyObject {
    func selectedText() async throws -> String
    func accessibilityPermissionStatus(prompt: Bool) async -> Bool
}

@MainActor
final class SelectionCaptureCoordinator {
    private let draft: DraftStore
    private let provider: SelectionProviding
    private let onSuccess: () -> Void
    private let onFailure: (SelectionCaptureError) -> Void
    private var isCapturing = false

    init(
        draft: DraftStore,
        provider: SelectionProviding,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping (SelectionCaptureError) -> Void
    ) {
        self.draft = draft
        self.provider = provider
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    func captureSelection() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let text = try await provider.selectedText()
            try draft.addSelectedText(text)
            onSuccess()
        } catch let error as SelectionCaptureError {
            onFailure(error)
        } catch {
            onFailure(.unavailable)
        }
    }
}
