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

    func trashedThoughts() throws -> [Thought] {
        let descriptor = FetchDescriptor<Thought>(
            sortBy: [SortDescriptor(\Thought.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { $0.trashedAt != nil }
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
        _ = try move([thought], to: project, saveChanges: saveChanges)
    }

    @discardableResult
    func move(
        _ thoughts: [Thought],
        to project: Project?,
        saveChanges: (() throws -> Void)? = nil
    ) throws -> Int {
        let uniqueThoughts = unique(thoughts).filter { $0.trashedAt == nil }
        let changes = uniqueThoughts.compactMap { thought -> (Thought, Project?, UUID?)? in
            guard thought.project?.id != project?.id else { return nil }
            return (thought, thought.project, thought.formerProjectID)
        }
        guard !changes.isEmpty else { return 0 }
        for (thought, _, _) in changes {
            thought.project = project
            thought.formerProjectID = nil
        }
        do {
            try save(saveChanges)
        } catch {
            for (thought, previousProject, previousFormerProjectID) in changes {
                thought.project = previousProject
                thought.formerProjectID = previousFormerProjectID
            }
            throw error
        }
        return changes.count
    }

    func trash(
        _ thought: Thought,
        at date: Date = .now,
        saveChanges: (() throws -> Void)? = nil
    ) throws {
        _ = try trash([thought], at: date, saveChanges: saveChanges)
    }

    @discardableResult
    func trash(
        _ thoughts: [Thought],
        at date: Date = .now,
        saveChanges: (() throws -> Void)? = nil
    ) throws -> Int {
        let uniqueThoughts = unique(thoughts).filter { $0.trashedAt == nil }
        guard !uniqueThoughts.isEmpty else { return 0 }
        let previous = uniqueThoughts.map {
            (thought: $0, project: $0.project, formerProjectID: $0.formerProjectID, trashedAt: $0.trashedAt)
        }
        for thought in uniqueThoughts {
            thought.formerProjectID = thought.project?.id
            thought.project = nil
            thought.trashedAt = date
        }
        do {
            try save(saveChanges)
        } catch {
            for state in previous {
                state.thought.project = state.project
                state.thought.formerProjectID = state.formerProjectID
                state.thought.trashedAt = state.trashedAt
            }
            throw error
        }
        return uniqueThoughts.count
    }

    func restore(
        _ thought: Thought,
        saveChanges: (() throws -> Void)? = nil
    ) throws -> RestoreResult {
        try restore([thought], saveChanges: saveChanges)
    }

    @discardableResult
    func restore(
        _ thoughts: [Thought],
        saveChanges: (() throws -> Void)? = nil
    ) throws -> RestoreResult {
        let uniqueThoughts = unique(thoughts).filter { $0.trashedAt != nil }
        guard !uniqueThoughts.isEmpty else {
            return RestoreResult(restoredCount: 0, inboxFallbackCount: 0)
        }
        let projectsByID = Dictionary(uniqueKeysWithValues: try allProjects().map { ($0.id, $0) })
        let previous = uniqueThoughts.map {
            (thought: $0, project: $0.project, formerProjectID: $0.formerProjectID, trashedAt: $0.trashedAt)
        }
        var fallbackCount = 0
        for thought in uniqueThoughts {
            if let formerProjectID = thought.formerProjectID {
                if let project = projectsByID[formerProjectID] {
                    thought.project = project
                } else {
                    thought.project = nil
                    fallbackCount += 1
                }
            } else {
                thought.project = nil
            }
            thought.formerProjectID = nil
            thought.trashedAt = nil
        }
        do {
            try save(saveChanges)
        } catch {
            for state in previous {
                state.thought.project = state.project
                state.thought.formerProjectID = state.formerProjectID
                state.thought.trashedAt = state.trashedAt
            }
            throw error
        }
        return RestoreResult(restoredCount: uniqueThoughts.count, inboxFallbackCount: fallbackCount)
    }

    @discardableResult
    func permanentlyDelete(
        _ thoughts: [Thought],
        saveChanges: (() throws -> Void)? = nil
    ) throws -> Int {
        let uniqueThoughts = unique(thoughts)
        let activeCount = uniqueThoughts.filter { $0.trashedAt == nil }.count
        guard activeCount == 0 else {
            throw TrashError.onlyTrashCanBePermanentlyDeleted(count: activeCount)
        }
        guard !uniqueThoughts.isEmpty else { return 0 }
        context.processPendingChanges()
        let previousUndoManager = context.undoManager
        let deletionUndoManager = UndoManager()
        context.undoManager = deletionUndoManager
        defer { context.undoManager = previousUndoManager }
        deletionUndoManager.beginUndoGrouping()
        for thought in uniqueThoughts {
            context.delete(thought)
        }
        deletionUndoManager.endUndoGrouping()
        do {
            try save(saveChanges)
            deletionUndoManager.removeAllActions()
        } catch {
            deletionUndoManager.undo()
            throw error
        }
        return uniqueThoughts.count
    }

    func projectDeletionImpact(for project: Project) throws -> ProjectDeletionImpact {
        let activeCount = try allThoughts().filter { $0.project?.id == project.id }.count
        let trashedCount = try trashedThoughts().filter { $0.formerProjectID == project.id }.count
        return ProjectDeletionImpact(activeThoughtCount: activeCount, trashedThoughtCount: trashedCount)
    }

    @discardableResult
    func deleteProject(
        _ project: Project,
        draft: DraftStore?,
        saveChanges: (() throws -> Void)? = nil
    ) throws -> ProjectDeletionResult {
        let impact = try projectDeletionImpact(for: project)
        guard impact.activeThoughtCount == 0 else {
            throw TrashError.projectContainsActiveThoughts(count: impact.activeThoughtCount)
        }
        let resetsDraft = draft?.projectID == project.id
        context.processPendingChanges()
        let previousUndoManager = context.undoManager
        let deletionUndoManager = UndoManager()
        context.undoManager = deletionUndoManager
        defer { context.undoManager = previousUndoManager }
        deletionUndoManager.beginUndoGrouping()
        context.delete(project)
        deletionUndoManager.endUndoGrouping()
        do {
            try save(saveChanges)
            deletionUndoManager.removeAllActions()
        } catch {
            deletionUndoManager.undo()
            throw error
        }
        if resetsDraft {
            draft?.fallBackToInboxBecauseProjectIsUnavailable()
        }
        return ProjectDeletionResult(
            trashedThoughtCount: impact.trashedThoughtCount,
            draftDestinationReset: resetsDraft
        )
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
        let previousSearchableText = thought.searchableText
        let previousEditedAt = thought.editedAt
        thought.markdown = markdown
        thought.searchableText = MarkdownDocument(source: markdown).searchableText
        thought.editedAt = date
        do {
            if let saveChanges {
                try saveChanges()
            } else {
                try context.save()
            }
        } catch {
            thought.markdown = previousMarkdown
            thought.searchableText = previousSearchableText
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

    private func unique(_ thoughts: [Thought]) -> [Thought] {
        Dictionary(grouping: thoughts, by: \.id).compactMap(\.value.first)
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
            let container = try ModelContainer(for: Thought.self, Project.self, configurations: configuration)
            try backfillSearchableText(in: container)
            return container
        }

        let container = try ModelContainer(for: Thought.self, Project.self)
        try backfillSearchableText(in: container)
        return container
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

    @MainActor
    private static func backfillSearchableText(in container: ModelContainer) throws {
        let context = container.mainContext
        let thoughts = try context.fetch(FetchDescriptor<Thought>())
        var changed = false
        for thought in thoughts where thought.searchableText.isEmpty && thought.markdown.containsNonWhitespace {
            thought.searchableText = MarkdownDocument(source: thought.markdown).searchableText
            changed = true
        }
        if changed {
            try context.save()
        }
    }
}
