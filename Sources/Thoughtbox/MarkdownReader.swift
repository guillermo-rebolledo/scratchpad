import SwiftUI

struct MarkdownReader: View {
    let document: MarkdownDocument

    init(markdown: String) {
        document = MarkdownDocument(source: markdown)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rendered Thought")
        .accessibilityHint("Switch to Edit to change the raw Markdown source.")
        .accessibilityIdentifier("thought.rendered")
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    @ViewBuilder
    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(InlineMarkdown.attributed(text))
                .font(font(forHeadingLevel: level))
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

        case let .paragraph(text):
            Text(InlineMarkdown.attributed(text))
                .textSelection(.enabled)

        case let .blockQuote(blocks):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        AnyView(MarkdownBlockView(block: block))
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Block quote")

        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownListItemView(marker: "•", item: item)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Unordered list with \(items.count) items")

        case let .orderedList(start, items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    MarkdownListItemView(marker: "\(start + offset).", item: item)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Ordered list with \(items.count) items")

        case let .code(language, source):
            VStack(alignment: .leading, spacing: 4) {
                if let language {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(source)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(language.map { "\($0) code" } ?? "Code")
            .accessibilityValue(source)

        case let .table(headers, rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(InlineMarkdown.attributed(header))
                            .fontWeight(.semibold)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            Text(InlineMarkdown.attributed(cell))
                                .accessibilityLabel(tableCellLabel(
                                    header: headers.indices.contains(column) ? headers[column] : "Column \(column + 1)",
                                    value: cell
                                ))
                        }
                    }
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Table with \(headers.count) columns and \(rows.count) rows")

        case .thematicBreak:
            Divider()
                .accessibilityLabel("Section break")
        }
    }

    private func tableCellLabel(header: String, value: String) -> String {
        let plainHeader = MarkdownDocument.plainText(fromInlineMarkdown: header)
        let plainValue = MarkdownDocument.plainText(fromInlineMarkdown: value)
        return "\(plainHeader): \(plainValue)"
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: .largeTitle
        case 2: .title
        case 3: .title2
        case 4: .title3
        default: .headline
        }
    }
}

private struct MarkdownListItemView: View {
    let marker: String
    let item: MarkdownListItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let isComplete = item.isComplete {
                Image(systemName: isComplete ? "checkmark.square" : "square")
                    .frame(minWidth: 20, alignment: .trailing)
                    .accessibilityHidden(true)
            } else {
                Text(marker)
                    .frame(minWidth: 20, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                    AnyView(MarkdownBlockView(block: block))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.isComplete == nil ? "List item" : "Task checkboxes are visual. Switch to Edit to change the task.")
    }

    private var accessibilityLabel: String {
        guard let isComplete = item.isComplete else { return "List item" }
        return isComplete ? "Completed task" : "Incomplete task"
    }
}

enum InlineMarkdown {
    static func attributed(_ source: String) -> AttributedString {
        let safeSource = MarkdownDocument.replacingImages(in: source)
        let segments = safeSource.components(separatedBy: "~~")
        var result = AttributedString()

        for (index, segment) in segments.enumerated() {
            var attributed = (try? AttributedString(
                markdown: segment,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(segment)
            if index.isMultiple(of: 2) == false {
                attributed.strikethroughStyle = .single
            }
            result.append(attributed)
        }
        return result
    }
}
