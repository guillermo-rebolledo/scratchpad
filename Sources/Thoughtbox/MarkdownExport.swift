import AppKit
import Foundation

struct ExportProject: Equatable, Sendable {
    let id: UUID
    let name: String
}

struct ThoughtExportItem: Equatable, Sendable {
    let id: UUID
    let markdown: String
    let createdAt: Date
    let editedAt: Date
    let project: ExportProject?
    let isTrashed: Bool

    @MainActor
    init(thought: Thought) {
        id = thought.id
        markdown = thought.markdown
        createdAt = thought.createdAt
        editedAt = thought.editedAt
        project = thought.project.map { ExportProject(id: $0.id, name: $0.name) }
        isTrashed = thought.trashedAt != nil
    }

    init(
        id: UUID,
        markdown: String,
        createdAt: Date,
        editedAt: Date,
        project: ExportProject?,
        isTrashed: Bool
    ) {
        self.id = id
        self.markdown = markdown
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.project = project
        self.isTrashed = isTrashed
    }
}

enum ThoughtExportScope: Equatable, Sendable {
    case allActive
    case selectedTrash
}

struct PlannedMarkdownFile: Equatable, Sendable {
    let thoughtID: UUID
    let relativePath: String
    let content: String
}

struct MarkdownExportPlan: Equatable, Sendable {
    let files: [PlannedMarkdownFile]
}

struct MarkdownExportPlanner: Sendable {
    private let timeZone: TimeZone

    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    func makePlan(for items: [ThoughtExportItem], scope: ThoughtExportScope) -> MarkdownExportPlan {
        let included = items.filter { item in
            switch scope {
            case .allActive: !item.isTrashed
            case .selectedTrash: item.isTrashed
            }
        }
        let folderNames = resolvedFolderNames(for: included, scope: scope)
        let sorted = included.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var candidates: [Candidate] = []
        for item in sorted {
            if Task.isCancelled { return MarkdownExportPlan(files: []) }
            let folderKey = folderKey(for: item, scope: scope)
            let timestamp = filenameTimestamp(item.createdAt)
            let slug = Self.slug(from: item.markdown)
            candidates.append(Candidate(
                item: item,
                folder: folderNames[folderKey] ?? "Inbox",
                baseFilename: "\(timestamp)-\(slug)"
            ))
        }
        let collisionGroups = Dictionary(grouping: candidates) {
            "\($0.folder)/\($0.baseFilename)".normalizedExportCollisionKey
        }

        let files = candidates.map { candidate -> PlannedMarkdownFile in
            let collisionKey = "\(candidate.folder)/\(candidate.baseFilename)".normalizedExportCollisionKey
            let peers = collisionGroups[collisionKey, default: []]
            let suffix = peers.count > 1
                ? "-\(Self.uniqueStableSuffix(candidate.item.id, among: peers.map { $0.item.id }))"
                : ""
            return PlannedMarkdownFile(
                thoughtID: candidate.item.id,
                relativePath: "\(candidate.folder)/\(candidate.baseFilename)\(suffix).md",
                content: frontMatter(for: candidate.item) + candidate.item.markdown
            )
        }
        return MarkdownExportPlan(files: files)
    }

    private func resolvedFolderNames(
        for items: [ThoughtExportItem],
        scope: ThoughtExportScope
    ) -> [String: String] {
        if case .selectedTrash = scope { return ["trash": "Trash"] }

        let projects = Dictionary(
            grouping: items.compactMap(\.project),
            by: \.id
        ).compactMap(\.value.first)
        let candidates = projects.map { project in
            (project: project, sanitized: Self.portableComponent(project.name, fallback: "Project"))
        }
        let groups = Dictionary(grouping: candidates) { $0.sanitized.normalizedExportCollisionKey }
        var result = ["inbox": "Inbox"]
        for candidate in candidates {
            let key = candidate.sanitized.normalizedExportCollisionKey
            let conflictsWithReserved = key == "inbox" || key == "trash"
            let peers = groups[key, default: []]
            let needsSuffix = conflictsWithReserved || peers.count > 1
            let suffix = Self.uniqueStableSuffix(
                candidate.project.id,
                among: peers.map { $0.project.id }
            )
            result["project:\(candidate.project.id.uuidString)"] = needsSuffix
                ? "\(candidate.sanitized)-\(suffix)"
                : candidate.sanitized
        }
        return result
    }

    private func folderKey(for item: ThoughtExportItem, scope: ThoughtExportScope) -> String {
        if case .selectedTrash = scope { return "trash" }
        return item.project.map { "project:\($0.id.uuidString)" } ?? "inbox"
    }

    private func filenameTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private func frontMatter(for item: ThoughtExportItem) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return "---\nid: \"\(item.id.uuidString)\"\ncreated_at: \"\(formatter.string(from: item.createdAt))\"\nedited_at: \"\(formatter.string(from: item.editedAt))\"\n---\n\n"
    }

    private static func slug(from markdown: String) -> String {
        let plainText = MarkdownDocument(source: markdown).searchableText
        let words = plainText.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter(\.containsNonWhitespace)
            .prefix(6)
        let joined = words.joined(separator: "-").lowercased()
        return portableComponent(joined, fallback: "thought")
    }

    private static func portableComponent(
        _ value: String,
        fallback: String,
        maximumUTF8Bytes: Int = 160,
        maximumUTF16Units: Int = 160
    ) -> String {
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*")
            .union(.controlCharacters)
        var output = ""
        var pendingSeparator = false
        for scalar in value.unicodeScalars {
            if invalid.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSeparator = !output.isEmpty
            } else {
                if pendingSeparator, output.last != "-" { output.append("-") }
                output.unicodeScalars.append(scalar)
                pendingSeparator = false
            }
        }
        output = output.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        var portable = ""
        for character in output {
            let candidate = portable + String(character)
            guard candidate.utf8.count <= maximumUTF8Bytes,
                  candidate.utf16.count <= maximumUTF16Units else { break }
            portable = candidate
        }
        output = portable.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        let deviceBasename = output.split(separator: ".", maxSplits: 1).first.map(String.init)?.lowercased()
        if output.isEmpty || deviceBasename.map(Self.reservedFilenames.contains) == true {
            return fallback
        }
        return output
    }

    private static func uniqueStableSuffix(_ id: UUID, among ids: [UUID]) -> String {
        let values = ids.map { $0.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
        let value = id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        for length in stride(from: 8, through: 32, by: 4) {
            let prefix = String(value.prefix(length))
            if values.filter({ $0.hasPrefix(prefix) }).count == 1 {
                return prefix
            }
        }
        return value
    }

    private static let reservedFilenames: Set<String> = [
        ".", "..", "con", "prn", "aux", "nul",
        "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
        "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"
    ]

    private struct Candidate {
        let item: ThoughtExportItem
        let folder: String
        let baseFilename: String
    }
}

struct MarkdownExportFailure: Error, Equatable, Sendable {
    let relativePath: String
    let message: String
}

struct MarkdownExportResult: Equatable, Sendable {
    let writtenRelativePaths: [String]
    let failures: [MarkdownExportFailure]
    let wasCancelled: Bool

    init(
        writtenRelativePaths: [String],
        failures: [MarkdownExportFailure],
        wasCancelled: Bool = false
    ) {
        self.writtenRelativePaths = writtenRelativePaths
        self.failures = failures
        self.wasCancelled = wasCancelled
    }

    var isFullSuccess: Bool { failures.isEmpty && !wasCancelled }
}

struct MarkdownExportWriter {
    typealias WriteData = (Data, URL) throws -> Void

    private let fileManager: FileManager
    private let writeData: WriteData

    init(
        fileManager: FileManager = .default,
        writeData: @escaping WriteData = { data, url in
            let temporaryURL = url.deletingLastPathComponent()
                .appending(path: ".thoughtbox-export-\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try data.write(to: temporaryURL, options: .atomic)
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    ) {
        self.fileManager = fileManager
        self.writeData = writeData
    }

    func write(_ plan: MarkdownExportPlan, to destination: URL) -> MarkdownExportResult {
        var written: [String] = []
        var failures: [MarkdownExportFailure] = []

        for file in plan.files {
            if Task.isCancelled {
                return MarkdownExportResult(
                    writtenRelativePaths: written,
                    failures: failures,
                    wasCancelled: true
                )
            }
            guard Self.isSafeRelativePath(file.relativePath) else {
                failures.append(.init(relativePath: file.relativePath, message: "Unsafe output path."))
                continue
            }
            let output = availableOutput(for: file, in: destination)
            switch output {
            case let .success((relativePath, url)):
                do {
                    try fileManager.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try writeData(Data(file.content.utf8), url)
                    written.append(relativePath)
                } catch {
                    failures.append(.init(
                        relativePath: relativePath,
                        message: "Could not write this output."
                    ))
                }
            case let .failure(failure):
                failures.append(failure)
            }
        }
        return MarkdownExportResult(writtenRelativePaths: written, failures: failures)
    }

    private func availableOutput(
        for file: PlannedMarkdownFile,
        in destination: URL
    ) -> Result<(String, URL), MarkdownExportFailure> {
        let requestedURL = destination.appending(path: file.relativePath)
        guard fileManager.fileExists(atPath: requestedURL.path) else {
            return .success((file.relativePath, requestedURL))
        }
        if existingOutput(at: requestedURL, hasStableID: file.thoughtID) {
            return .failure(.init(
                relativePath: file.relativePath,
                message: "An export with this stable ID already exists. No file was overwritten."
            ))
        }

        let relativePath = file.relativePath as NSString
        let stem = (relativePath.lastPathComponent as NSString).deletingPathExtension
        let stableID = file.thoughtID.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let suffixLengths = Array(stride(from: 8, through: 32, by: 4))
        let parent = relativePath.deletingLastPathComponent
        for length in suffixLengths {
            let collisionName = "\(stem)-\(stableID.prefix(length)).md"
            let collisionPath = parent == "." ? collisionName : "\(parent)/\(collisionName)"
            let collisionURL = destination.appending(path: collisionPath)
            if !fileManager.fileExists(atPath: collisionURL.path) {
                return .success((collisionPath, collisionURL))
            }
            if existingOutput(at: collisionURL, hasStableID: file.thoughtID) {
                return .failure(.init(
                    relativePath: collisionPath,
                    message: "An export with this stable ID already exists. No file was overwritten."
                ))
            }
        }
        return .failure(.init(
            relativePath: file.relativePath,
            message: "An export with this stable ID already exists. No file was overwritten."
        ))
    }

    private func existingOutput(at url: URL, hasStableID id: UUID) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let lines = contents.split(whereSeparator: \Character.isNewline)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return false }
        var foundStableID = false
        for line in lines.dropFirst() {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value == "---" { return foundStableID }
            if value == "id: \"\(id.uuidString)\"" { foundStableID = true }
        }
        return false
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

enum MarkdownExportOutcome: Equatable, Sendable {
    case cancelled
    case completed(MarkdownExportResult)
}

struct MarkdownExportService {
    private let writer: MarkdownExportWriter

    init(writer: MarkdownExportWriter = MarkdownExportWriter()) {
        self.writer = writer
    }

    func export(_ plan: MarkdownExportPlan, to destination: URL?) -> MarkdownExportOutcome {
        guard let destination else { return .cancelled }
        let isAccessingSecurityScopedResource = destination.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        return .completed(writer.write(plan, to: destination))
    }
}

@MainActor
struct SystemExportDestinationPicker {
    func chooseDestination() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Export Thoughtbox Markdown"
        panel.message = "Choose a folder. Thoughtbox will create Inbox and Project folders inside it."
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}

private extension String {
    var normalizedExportCollisionKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
