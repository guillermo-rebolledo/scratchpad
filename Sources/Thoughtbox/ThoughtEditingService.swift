import Foundation

@MainActor
struct ThoughtEditingService {
    private let repository: ThoughtRepository

    init(repository: ThoughtRepository) {
        self.repository = repository
    }

    func update(_ thought: Thought, markdown: String, at date: Date = .now) throws {
        try repository.update(thought, markdown: markdown, at: date)
    }
}

