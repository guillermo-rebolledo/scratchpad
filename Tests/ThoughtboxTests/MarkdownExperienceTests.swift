import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct MarkdownExperienceTests {
    @Test("Markdown becomes readable blocks without loading images")
    func parsesSupportedMarkdownSafely() throws {
        let source = #"""
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

        ![a\]b](https://tracker.example/escaped.png)
        """#

        let document = MarkdownDocument(source: source)

        #expect(document.blocks.contains(.heading(level: 1, text: "Heading")))
        #expect(document.blocks.contains { block in
            guard case let .unorderedList(items) = block else { return false }
            return items.contains { $0.isComplete == false && $0.blocks.contains(.paragraph("visual task")) }
        })
        #expect(document.blocks.contains { block in
            guard case let .code(language, code) = block else { return false }
            return language == "swift" && code.trimmingCharacters(in: .whitespacesAndNewlines) == "let answer = 42"
        })
        #expect(document.blocks.contains(.table(headers: ["Name", "Value"], rows: [["One", "Two"]])))
        #expect(document.renderableSource.contains("Image not loaded: private"))
        #expect(!document.renderableSource.contains("https://tracker.example/pixel.png"))
        #expect(!document.renderableSource.contains("https://tracker.example/escaped.png"))
    }

    @Test("Excerpt removes Markdown syntax and limits itself to two lines")
    func createsPlainTextExcerpt() {
        let source = "# Heading\n\nFirst **important** line with [context](https://example.com).\n\nThird line"

        #expect(MarkdownDocument(source: source).excerpt == "Heading\nFirst important line with context.")
        #expect(MarkdownDocument(source: "file_name computes 2 * 3").excerpt == "file_name computes 2 * 3")
    }

    @Test("CommonMark multiline and nested blocks keep their structure")
    func parsesCommonMarkStructures() {
        let source = #"""
        > Quoted first line
        >
        > - nested item

            indented code

        ~~~~text
        fenced with tildes
        ~~~~

        1234. valid ordered item
        """#

        let document = MarkdownDocument(source: source)

        #expect(document.blocks.contains { if case .blockQuote = $0 { true } else { false } })
        #expect(document.blocks.filter { if case .code = $0 { true } else { false } }.count == 2)
        #expect(document.blocks.contains { block in
            guard case let .orderedList(start, _) = block else { return false }
            return start == 1234
        })
    }

    @Test("Editing updates edit time without changing creation order")
    func editingPreservesCreationOrder() throws {
        let repository = try ThoughtRepository.inMemory()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let editedAt = createdAt.addingTimeInterval(300)
        let thought = try repository.capture(markdown: "Before", at: createdAt)
        try repository.update(thought, markdown: "After", at: editedAt)

        #expect(thought.markdown == "After")
        #expect(thought.createdAt == createdAt)
        #expect(thought.editedAt == editedAt)
        #expect(repository.allThoughts().first?.id == thought.id)
    }
}
