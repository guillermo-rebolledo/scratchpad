import Foundation
import Testing
@testable import Thoughtbox

struct MarkdownExportTests {
    private let utc = TimeZone(secondsFromGMT: 0)!

    @Test("Export All groups active canonical Markdown and excludes Trash")
    func activeGroupingAndTrashExclusion() throws {
        let createdAt = Date(timeIntervalSince1970: 1_704_164_645)
        let editedAt = createdAt.addingTimeInterval(90)
        let inbox = ThoughtExportItem(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            markdown: "# Inbox title\n\nCanonical **source**",
            createdAt: createdAt,
            editedAt: editedAt,
            project: nil,
            isTrashed: false
        )
        let project = ThoughtExportItem(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            markdown: "Project words",
            createdAt: createdAt,
            editedAt: createdAt,
            project: .init(id: UUID(), name: "Work/Personal"),
            isTrashed: false
        )
        let trash = ThoughtExportItem(
            id: UUID(),
            markdown: "Excluded trash",
            createdAt: createdAt,
            editedAt: createdAt,
            project: nil,
            isTrashed: true
        )

        let plan = MarkdownExportPlanner(timeZone: utc).makePlan(
            for: [trash, project, inbox],
            scope: .allActive
        )

        #expect(plan.files.count == 2)
        #expect(plan.files.map(\.relativePath).contains("Inbox/2024-01-02_03-04-05-inbox-title-canonical-source.md"))
        #expect(plan.files.map(\.relativePath).contains("Work-Personal/2024-01-02_03-04-05-project-words.md"))
        let inboxFile = try #require(plan.files.first { $0.thoughtID == inbox.id })
        #expect(inboxFile.content == """
        ---
        id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        created_at: "2024-01-02T03:04:05Z"
        edited_at: "2024-01-02T03:05:35Z"
        ---

        # Inbox title

        Canonical **source**
        """)
    }

    @Test("Explicit Trash export contains only selected trashed Thoughts")
    func selectedTrashOnly() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let active = ThoughtExportItem(
            id: UUID(), markdown: "Active", createdAt: date, editedAt: date, project: nil, isTrashed: false
        )
        let trash = ThoughtExportItem(
            id: UUID(), markdown: "Trash export", createdAt: date, editedAt: date, project: nil, isTrashed: true
        )

        let plan = MarkdownExportPlanner(timeZone: utc).makePlan(for: [active, trash], scope: .selectedTrash)

        #expect(plan.files.count == 1)
        #expect(plan.files[0].thoughtID == trash.id)
        #expect(plan.files[0].relativePath.hasPrefix("Trash/"))
    }

    @Test("Portable names sanitize reserved characters and use stable suffixes for collisions")
    func sanitizationAndCollisions() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let projectID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let items = [firstID, secondID].map { id in
            ThoughtExportItem(
                id: id,
                markdown: "Same: title? words*",
                createdAt: date,
                editedAt: date,
                project: .init(id: projectID, name: "Inbox"),
                isTrashed: false
            )
        }

        let plan = MarkdownExportPlanner(timeZone: utc).makePlan(for: items, scope: .allActive)

        #expect(plan.files.map(\.relativePath) == [
            "Inbox-cccccccc/2023-11-14_22-13-20-same-title-words-11111111.md",
            "Inbox-cccccccc/2023-11-14_22-13-20-same-title-words-22222222.md"
        ])
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxExportCollisionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = MarkdownExportWriter().write(plan, to: destination)
        #expect(result.isFullSuccess)
        #expect(result.writtenRelativePaths.count == 2)
        #expect(try String(contentsOf: destination.appending(path: result.writtenRelativePaths[0]), encoding: .utf8)
            .contains("Same: title? words*"))
        #expect(try String(contentsOf: destination.appending(path: result.writtenRelativePaths[1]), encoding: .utf8)
            .contains("Same: title? words*"))
    }

    @Test("Writer creates an inspectable artifact and never overwrites an existing collision")
    func externalArtifactAndExistingCollision() throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let id = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let file = PlannedMarkdownFile(
            thoughtID: id,
            relativePath: "Inbox/2024-01-02_03-04-05-portable.md",
            content: "portable artifact"
        )
        let baseURL = destination.appending(path: file.relativePath)
        try FileManager.default.createDirectory(at: baseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing content".utf8).write(to: baseURL)

        let result = MarkdownExportWriter().write(.init(files: [file]), to: destination)

        #expect(result.failures.isEmpty)
        #expect(result.writtenRelativePaths == ["Inbox/2024-01-02_03-04-05-portable-dddddddd.md"])
        #expect(try String(contentsOf: baseURL, encoding: .utf8) == "existing content")
        let exportedURL = destination.appending(path: result.writtenRelativePaths[0])
        #expect(try String(contentsOf: exportedURL, encoding: .utf8) == "portable artifact")
    }

    @Test("Write failures identify the affected output and cannot report full success")
    func writeFailureReporting() {
        struct SimulatedFailure: Error {}

        let first = PlannedMarkdownFile(thoughtID: UUID(), relativePath: "Inbox/first.md", content: "first")
        let second = PlannedMarkdownFile(thoughtID: UUID(), relativePath: "Inbox/second.md", content: "second")
        let writer = MarkdownExportWriter { data, url in
            if url.lastPathComponent == "second.md" { throw SimulatedFailure() }
            try data.write(to: url, options: .atomic)
        }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxExportFailureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }

        let result = writer.write(.init(files: [first, second]), to: destination)

        #expect(result.isFullSuccess == false)
        #expect(result.writtenRelativePaths == ["Inbox/first.md"])
        #expect(result.failures.map(\.relativePath) == ["Inbox/second.md"])
    }

    @Test("A canceled destination performs no writes")
    func cancellation() {
        var writeAttempted = false
        let writer = MarkdownExportWriter { _, _ in writeAttempted = true }
        let service = MarkdownExportService(writer: writer)
        let file = PlannedMarkdownFile(thoughtID: UUID(), relativePath: "Inbox/canceled.md", content: "no write")

        let outcome = service.export(.init(files: [file]), to: nil)

        #expect(outcome == .cancelled)
        #expect(writeAttempted == false)
    }
}
