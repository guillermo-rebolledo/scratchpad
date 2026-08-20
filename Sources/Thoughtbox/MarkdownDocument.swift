import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case blockQuote(String)
    case unorderedListItem(String)
    case orderedListItem(number: Int, text: String)
    case taskListItem(isComplete: Bool, text: String)
    case code(language: String?, source: String)
    case table(headers: [String], rows: [[String]])

    var plainText: String {
        switch self {
        case let .heading(_, text), let .paragraph(text), let .blockQuote(text),
             let .unorderedListItem(text), let .orderedListItem(_, text),
             let .taskListItem(_, text):
            MarkdownDocument.plainText(fromInlineMarkdown: text)
        case let .code(_, source):
            source
        case let .table(headers, rows):
            ([headers] + rows).flatMap { $0 }.joined(separator: " ")
        }
    }
}

struct MarkdownDocument {
    let source: String
    let renderableSource: String
    let blocks: [MarkdownBlock]

    init(source: String) {
        self.source = source
        renderableSource = Self.replacingImages(in: source)
        blocks = Self.parse(renderableSource)
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

    static func replacingImages(in source: String) -> String {
        let pattern = #"!\[([^\]]*)\]\([^\)]*\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return expression.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "Image not loaded: $1"
        )
    }

    static func plainText(fromInlineMarkdown source: String) -> String {
        var result = replacingImages(in: source)
        result = replacing(pattern: #"\[([^\]]+)\]\([^\)]*\)"#, in: result, with: "$1")
        result = replacing(pattern: #"[*_~`]"#, in: result, with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(pattern: String, in source: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        return expression.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: template
        )
    }

    private static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: language.isEmpty ? nil : language, source: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if index + 1 < lines.count,
               let headers = tableCells(from: trimmed),
               isTableSeparator(lines[index + 1]),
               headers.count > 1 {
                index += 2
                var rows: [[String]] = []
                while index < lines.count, let cells = tableCells(from: lines[index]), !cells.isEmpty {
                    rows.append(cells)
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                blocks.append(.blockQuote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let task = taskListItem(from: trimmed) {
                blocks.append(task)
            } else if let item = unorderedListItem(from: trimmed) {
                blocks.append(.unorderedListItem(item))
            } else if let item = orderedListItem(from: trimmed) {
                blocks.append(item)
            } else {
                blocks.append(.paragraph(trimmed))
            }
            index += 1
        }

        return blocks
    }

    private static func heading(from line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return .heading(level: hashes.count, text: String(line.dropFirst(hashes.count + 1)))
    }

    private static func taskListItem(from line: String) -> MarkdownBlock? {
        guard line.count >= 6, line.hasPrefix("- [") || line.hasPrefix("* [") else { return nil }
        let characters = Array(line)
        guard characters[3] == "x" || characters[3] == "X" || characters[3] == " ", characters[4] == "]" else {
            return nil
        }
        return .taskListItem(isComplete: characters[3] != " ", text: String(characters.dropFirst(6)))
    }

    private static func unorderedListItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> MarkdownBlock? {
        guard let dot = line.firstIndex(of: "."), dot < line.index(line.startIndex, offsetBy: min(4, line.count)) else {
            return nil
        }
        let numberText = line[..<dot]
        guard let number = Int(numberText), line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        return .orderedListItem(number: number, text: String(line[line.index(dot, offsetBy: 2)...]))
    }

    private static func tableCells(from line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard let cells = tableCells(from: line), !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let normalized = cell.replacingOccurrences(of: ":", with: "")
            return normalized.count >= 3 && normalized.allSatisfy { $0 == "-" }
        }
    }
}

