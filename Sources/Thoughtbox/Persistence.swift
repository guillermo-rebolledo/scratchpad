import Foundation
import SwiftData

@MainActor
final class ThoughtRepository {
    let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
    }

    convenience init(context: ModelContext) {
        self.init(container: context.container, context: context)
    }

    private init(container: ModelContainer, context: ModelContext) {
        self.container = container
        self.context = context
    }

    static func inMemory() throws -> ThoughtRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Thought.self, configurations: configuration)
        return ThoughtRepository(container: container)
    }

    @discardableResult
    func capture(markdown: String, at date: Date = .now) throws -> Thought {
        guard markdown.containsNonWhitespace else {
            throw CaptureError.emptyThought
        }

        let thought = Thought(markdown: markdown, createdAt: date)
        context.insert(thought)
        try context.save()
        return thought
    }

    func allThoughts() throws -> [Thought] {
        let descriptor = FetchDescriptor<Thought>(
            sortBy: [SortDescriptor(\Thought.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func update(
        _ thought: Thought,
        markdown: String,
        at date: Date = .now,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        guard markdown.containsNonWhitespace else {
            throw CaptureError.emptyThought
        }
        guard thought.markdown != markdown else { return }
        let previousMarkdown = thought.markdown
        let previousEditedAt = thought.editedAt
        thought.markdown = markdown
        thought.editedAt = date
        do {
            if let saveChanges {
                try saveChanges()
            } else {
                try context.save()
            }
        } catch {
            thought.markdown = previousMarkdown
            thought.editedAt = previousEditedAt
            throw error
        }
    }
}

enum PersistenceFactory {
    @MainActor
    static func makeContainer(processInfo: ProcessInfo = .processInfo) throws -> ModelContainer {
        if processInfo.arguments.contains("--ui-testing") {
            let session = processInfo.environment["THOUGHTBOX_UI_TEST_SESSION"] ?? "default"
            let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appending(path: "ThoughtboxUITests", directoryHint: .isDirectory)
                .appending(path: session, directoryHint: .isDirectory)

            if processInfo.arguments.contains("--reset-ui-test-store") {
                try? FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: directory.appending(path: "Thoughtbox.store"))
            return try ModelContainer(for: Thought.self, configurations: configuration)
        }

        return try ModelContainer(for: Thought.self)
    }

    static func makeDraftDefaults(processInfo: ProcessInfo = .processInfo) -> UserDefaults {
        guard processInfo.arguments.contains("--ui-testing") else { return .standard }
        let session = processInfo.environment["THOUGHTBOX_UI_TEST_SESSION"] ?? "default"
        let suiteName = "com.memoji.Thoughtbox.UITests.\(session)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if processInfo.arguments.contains("--reset-ui-test-store") {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
