import Foundation

@MainActor
struct CaptureService {
    private let draft: DraftStore
    private let persist: (String, UUID?) throws -> Void

    init(draft: DraftStore, persist: @escaping (String) throws -> Void) {
        self.init(draft: draft) { markdown, _ in try persist(markdown) }
    }

    init(draft: DraftStore, persist: @escaping (String, UUID?) throws -> Void) {
        self.draft = draft
        self.persist = persist
    }

    func save() throws {
        guard draft.canSave else { throw CaptureError.emptyThought }
        try persist(draft.markdown, draft.projectID)
        draft.clear()
    }
}
