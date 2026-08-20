import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct MarkdownExperienceTests {
    @Test("Markdown becomes readable blocks without loading images")
    func parsesSupportedMarkdownSafely() throws {
        let source = """
        # Heading

        A **bold** paragraph with [a link](https://example.com) and ![private](https://tracker.example/pixel.png).

        > Quoted idea

        - [ ] visual task
        - list item

        | Name | Value |
        | --- | --- |
        | One | Two |

        ```swift
        let answer = 42
        ```
        """

        let document = MarkdownDocument(source: source)

        #expect(document.blocks.contains(.heading(level: 1, text: "Heading")))
        #expect(document.blocks.contains(.taskListItem(isComplete: false, text: "visual task")))
        #expect(document.blocks.contains(.code(language: "swift", source: "let answer = 42")))
        #expect(document.blocks.contains(.table(headers: ["Name", "Value"], rows: [["One", "Two"]])))
        #expect(document.renderableSource.contains("Image not loaded: private"))
        #expect(!document.renderableSource.contains("https://tracker.example/pixel.png"))
    }

    @Test("Excerpt removes Markdown syntax and limits itself to two lines")
    func createsPlainTextExcerpt() {
        let source = "# Heading\n\nFirst **important** line with [context](https://example.com).\n\nThird line"

        #expect(MarkdownDocument(source: source).excerpt == "Heading\nFirst important line with context.")
    }

    @Test("Editing updates edit time without changing creation order")
    func editingPreservesCreationOrder() throws {
        let repository = try ThoughtRepository.inMemory()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let editedAt = createdAt.addingTimeInterval(300)
        let thought = try repository.capture(markdown: "Before", at: createdAt)
        let service = ThoughtEditingService(repository: repository)

        try service.update(thought, markdown: "After", at: editedAt)

        #expect(thought.markdown == "After")
        #expect(thought.createdAt == createdAt)
        #expect(thought.editedAt == editedAt)
        #expect(repository.allThoughts().first?.id == thought.id)
    }
}
