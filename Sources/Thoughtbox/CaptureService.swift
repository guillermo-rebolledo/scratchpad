@MainActor
struct CaptureService {
    private let draft: DraftStore
    private let persist: (String) throws -> Void

    init(draft: DraftStore, persist: @escaping (String) throws -> Void) {
        self.draft = draft
        self.persist = persist
    }

    func save() throws {
        guard draft.canSave else { throw CaptureError.emptyThought }
        try persist(draft.markdown)
        draft.clear()
    }
}

