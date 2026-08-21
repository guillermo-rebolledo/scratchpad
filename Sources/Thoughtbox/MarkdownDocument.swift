import Foundation
import Markdown

struct MarkdownListItem: Equatable {
    let isComplete: Bool?
    let blocks: [MarkdownBlock]
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case blockQuote([MarkdownBlock])
    case unorderedList([MarkdownListItem])
    case orderedList(start: Int, items: [MarkdownListItem])
    case code(language: String?, source: String)
    case table(headers: [String], rows: [[String]])
    case thematicBreak

    var plainText: String {
        switch self {
        case let .heading(_, text), let .paragraph(text):
            MarkdownDocument.plainText(fromInlineMarkdown: text)
        case let .blockQuote(blocks):
            blocks.map(\.plainText).joined(separator: " ")
        case let .unorderedList(items), let .orderedList(_, items):
            items.flatMap(\.blocks).map(\.plainText).joined(separator: " ")
        case let .code(_, source):
            source
        case let .table(headers, rows):
            ([headers] + rows).flatMap { $0 }.map(Self.plainTableCell).joined(separator: " ")
        case .thematicBreak:
            ""
        }
    }

    private static func plainTableCell(_ source: String) -> String {
        MarkdownDocument.plainText(fromInlineMarkdown: source)
    }
}

struct MarkdownDocument {
    let source: String
    let renderableSource: String
    let blocks: [MarkdownBlock]

    init(source: String) {
        self.source = source
        let parsed = Document(parsing: source)
        var imageSanitizer = ImageSanitizer()
        let safeDocument = (imageSanitizer.visit(parsed) as? Document) ?? Document()
        renderableSource = safeDocument.format()
        blocks = Self.blocks(fromChildrenOf: safeDocument)
    }

    var excerpt: String {
        blocks
            .map(\.plainText)
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: "\n")
    }

    var searchableText: String {
        blocks.map(\.plainText)
            .filter(\.containsNonWhitespace)
            .joined(separator: "\n")
    }

    static func replacingImages(in source: String) -> String {
        MarkdownDocument(source: source).renderableSource
    }

    static func plainText(fromInlineMarkdown source: String) -> String {
        let document = Document(parsing: source)
        var imageSanitizer = ImageSanitizer()
        guard let safeDocument = imageSanitizer.visit(document) as? Document else { return source }
        var visitor = PlainTextVisitor()
        return visitor.text(from: safeDocument).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blocks(fromChildrenOf markup: Markup) -> [MarkdownBlock] {
        markup.children.flatMap(blocks(from:))
    }

    private static func blocks(from markup: Markup) -> [MarkdownBlock] {
        switch markup {
        case let heading as Heading:
            [.heading(level: heading.level, text: inlineMarkdown(from: heading))]
        case let paragraph as Paragraph:
            [.paragraph(inlineMarkdown(from: paragraph))]
        case let quote as BlockQuote:
            [.blockQuote(blocks(fromChildrenOf: quote))]
        case let list as UnorderedList:
            [.unorderedList(list.listItems.map(listItem(from:)))]
        case let list as OrderedList:
            [.orderedList(start: Int(list.startIndex), items: list.listItems.map(listItem(from:)))]
        case let code as CodeBlock:
            [.code(language: code.language, source: code.code)]
        case let table as Table:
            [.table(
                headers: table.head.cells.map(inlineMarkdown(from:)),
                rows: table.body.rows.map { $0.cells.map(inlineMarkdown(from:)) }
            )]
        case is ThematicBreak:
            [.thematicBreak]
        case let html as HTMLBlock:
            [.code(language: "html", source: html.rawHTML)]
        default:
            blocks(fromChildrenOf: markup)
        }
    }

    private static func listItem(from item: ListItem) -> MarkdownListItem {
        let isComplete: Bool?
        switch item.checkbox {
        case .checked: isComplete = true
        case .unchecked: isComplete = false
        case nil: isComplete = nil
        }
        return MarkdownListItem(isComplete: isComplete, blocks: blocks(fromChildrenOf: item))
    }

    private static func inlineMarkdown(from container: some InlineContainer) -> String {
        Paragraph(Array(container.inlineChildren)).format()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ThoughtSearch {
    static func filter(_ thoughts: [Thought], query: String) -> [Thought] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.containsNonWhitespace else { return thoughts }
        return thoughts.filter { $0.searchableText.localizedStandardContains(normalizedQuery) }
    }
}

private struct ImageSanitizer: MarkupRewriter {
    mutating func visitImage(_ image: Markdown.Image) -> Markup? {
        let altText = image.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Text("Image not loaded: \(altText.isEmpty ? "image" : altText)")
    }
}

private struct PlainTextVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitText(_ text: Markdown.Text) -> String { text.string }
    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String { inlineCode.code }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "\n" }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String { codeBlock.code }

    mutating func text(from markup: Markup) -> String {
        visit(markup)
    }
}
