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
        let container = try ModelContainer(for: Thought.self, Project.self, configurations: configuration)
        return ThoughtRepository(container: container)
    }

    @discardableResult
    func capture(
        markdown: String,
        at date: Date = .now,
        project: Project? = nil,
        saveChanges: (() throws -> Void)? = nil
    ) throws -> Thought {
        guard markdown.containsNonWhitespace else {
            throw CaptureError.emptyThought
        }

        let thought = Thought(markdown: markdown, createdAt: date, project: project)
        context.insert(thought)
        do {
            if let saveChanges {
                try saveChanges()
            } else {
                try context.save()
            }
            return thought
        } catch {
            context.delete(thought)
            throw error
        }
    }

    func allThoughts() throws -> [Thought] {
        let descriptor = FetchDescriptor<Thought>(
            sortBy: [SortDescriptor(\Thought.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { $0.trashedAt == nil }
    }

    func inboxThoughts() throws -> [Thought] {
        try allThoughts().filter { $0.project == nil }
    }

    func thoughts(in project: Project) throws -> [Thought] {
        try allThoughts().filter { $0.project?.id == project.id }
    }

    func allProjects() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\Project.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    func createProject(
        name: String,
        at date: Date = .now,
        saveChanges: (() throws -> Void)? = nil
    ) throws -> Project {
        let trimmedName = try validatedProjectName(name)
        let project = Project(name: trimmedName, createdAt: date)
        context.insert(project)
        do {
            try save(saveChanges)
            return project
        } catch {
            context.delete(project)
            throw error
        }
    }

    func renameProject(
        _ project: Project,
        to name: String,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        let trimmedName = try validatedProjectName(name, excluding: project.id)
        guard project.name != trimmedName else { return }
        let previousName = project.name
        project.name = trimmedName
        do {
            try save(saveChanges)
        } catch {
            project.name = previousName
            throw error
        }
    }

    func move(
        _ thought: Thought,
        to project: Project?,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        try move([thought], to: project, saveChanges: saveChanges)
    }

    func move(
        _ thoughts: [Thought],
        to project: Project?,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        let uniqueThoughts = Dictionary(grouping: thoughts, by: \.id).compactMap(\.value.first)
        let changes = uniqueThoughts.compactMap { thought -> (Thought, Project?)? in
            guard thought.project?.id != project?.id else { return nil }
            return (thought, thought.project)
        }
        guard !changes.isEmpty else { return }
        for (thought, _) in changes {
            thought.project = project
        }
        do {
            try save(saveChanges)
        } catch {
            for (thought, previousProject) in changes {
                thought.project = previousProject
            }
            throw error
        }
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

    private func validatedProjectName(_ name: String, excluding projectID: UUID? = nil) throws -> String {
        let trimmedName = name.trimmedProjectName
        guard trimmedName.containsNonWhitespace else { throw ProjectError.emptyName }
        let normalizedName = trimmedName.normalizedProjectName
        let duplicate = try allProjects().contains {
            $0.id != projectID && $0.name.normalizedProjectName == normalizedName
        }
        guard !duplicate else { throw ProjectError.duplicateName(trimmedName) }
        return trimmedName
    }

    private func save(_ saveChanges: (() throws -> Void)?) throws {
        if let saveChanges {
            try saveChanges()
        } else {
            try context.save()
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
            return try ModelContainer(for: Thought.self, Project.self, configurations: configuration)
        }

        return try ModelContainer(for: Thought.self, Project.self)
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
