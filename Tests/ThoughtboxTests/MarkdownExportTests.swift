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

    @Test("Repeating a collision export recognizes its existing stable-ID output")
    func repeatedExistingCollision() throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxRepeatedCollision-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let id = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let file = PlannedMarkdownFile(
            thoughtID: id,
            relativePath: "Inbox/portable.md",
            content: "---\nid: \"\(id.uuidString)\"\n---\n\nportable artifact"
        )
        let baseURL = destination.appending(path: file.relativePath)
        try FileManager.default.createDirectory(at: baseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unrelated existing file".utf8).write(to: baseURL)
        let writer = MarkdownExportWriter()
        let first = writer.write(.init(files: [file]), to: destination)

        let second = writer.write(.init(files: [file]), to: destination)

        #expect(first.writtenRelativePaths == ["Inbox/portable-dddddddd.md"])
        #expect(second.writtenRelativePaths.isEmpty)
        #expect(second.failures.map(\.relativePath) == ["Inbox/portable-dddddddd.md"])
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Inbox/portable-dddddddddddd.md").path) == false)
    }

    @Test("Stable-ID contents distinguish re-exports from unrelated suffixed files")
    func stableIDContentIdentity() throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxStableIDIdentity-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let id = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let content = "---\nid: \"\(id.uuidString)\"\n---\n\nportable artifact"
        let baseFile = PlannedMarkdownFile(
            thoughtID: id,
            relativePath: "Inbox/base.md",
            content: content
        )
        let writer = MarkdownExportWriter()
        let first = writer.write(.init(files: [baseFile]), to: destination)
        let repeated = writer.write(.init(files: [baseFile]), to: destination)

        #expect(first.writtenRelativePaths == ["Inbox/base.md"])
        #expect(repeated.writtenRelativePaths.isEmpty)
        #expect(repeated.failures.map(\.relativePath) == ["Inbox/base.md"])

        let suffixedFile = PlannedMarkdownFile(
            thoughtID: id,
            relativePath: "Inbox/suffixed-eeeeeeee.md",
            content: content
        )
        let suffixedURL = destination.appending(path: suffixedFile.relativePath)
        try Data("Unrelated note\n\nid: \"\(id.uuidString)\"\n\nThat line is body text.".utf8).write(to: suffixedURL)
        let suffixedResult = writer.write(.init(files: [suffixedFile]), to: destination)

        #expect(suffixedResult.writtenRelativePaths == ["Inbox/suffixed-eeeeeeee-eeeeeeee.md"])
        #expect(suffixedResult.failures.isEmpty)
    }

    @Test("Path components honor byte limits, Windows device names, and secondary stable-ID collisions")
    func deepPortabilityEdges() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let longProject = ExportProject(id: UUID(), name: String(repeating: "😀", count: 80))
        let reservedProject = ExportProject(id: UUID(), name: "CON.txt")
        let sharedPrefixOne = UUID(uuidString: "11111111-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let sharedPrefixTwo = UUID(uuidString: "11111111-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let items = [
            ThoughtExportItem(
                id: UUID(), markdown: "Long Project", createdAt: date, editedAt: date,
                project: longProject, isTrashed: false
            ),
            ThoughtExportItem(
                id: UUID(), markdown: "Reserved Project", createdAt: date, editedAt: date,
                project: reservedProject, isTrashed: false
            ),
            ThoughtExportItem(
                id: sharedPrefixOne, markdown: "Same collision", createdAt: date, editedAt: date,
                project: nil, isTrashed: false
            ),
            ThoughtExportItem(
                id: sharedPrefixTwo, markdown: "Same collision", createdAt: date, editedAt: date,
                project: nil, isTrashed: false
            )
        ]
        let plan = MarkdownExportPlanner(timeZone: utc).makePlan(for: items, scope: .allActive)
        let components = plan.files.flatMap { $0.relativePath.split(separator: "/").map(String.init) }
        #expect(components.allSatisfy { $0.utf8.count <= 255 && $0.utf16.count <= 255 })
        #expect(plan.files.contains { $0.relativePath.hasPrefix("Project/") })
        let collisionPaths = plan.files
            .filter { $0.thoughtID == sharedPrefixOne || $0.thoughtID == sharedPrefixTwo }
            .map(\.relativePath)
        #expect(Set(collisionPaths).count == 2)
        #expect(collisionPaths.contains { $0.contains("-11111111aaaa.md") })
        #expect(collisionPaths.contains { $0.contains("-11111111bbbb.md") })

        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxDeepPortability-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = MarkdownExportWriter().write(plan, to: destination)
        #expect(result.isFullSuccess)
        #expect(result.writtenRelativePaths.count == 4)
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

    @Test("An in-progress export stops between files when its task is canceled")
    func inProgressCancellation() async {
        let plan = MarkdownExportPlan(files: (0..<5_000).map { index in
            PlannedMarkdownFile(
                thoughtID: UUID(),
                relativePath: "Inbox/\(index).md",
                content: "cancel me"
            )
        })
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtboxExportCancellation-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let task = Task.detached {
            MarkdownExportWriter().write(plan, to: destination)
        }
        task.cancel()

        let result = await task.value

        #expect(result.wasCancelled)
        #expect(result.isFullSuccess == false)
        #expect(result.writtenRelativePaths.count < plan.files.count)
    }
}
