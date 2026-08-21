import Foundation
import SwiftData

@Model
final class Thought {
    @Attribute(.unique) var id: UUID
    var markdown: String
    var searchableText: String = ""
    var createdAt: Date
    var editedAt: Date
    var trashedAt: Date?
    var formerProjectID: UUID?
    var project: Project?

    init(
        id: UUID = UUID(),
        markdown: String,
        createdAt: Date = .now,
        editedAt: Date? = nil,
        trashedAt: Date? = nil,
        formerProjectID: UUID? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.markdown = markdown
        searchableText = MarkdownDocument(source: markdown).searchableText
        self.createdAt = createdAt
        self.editedAt = editedAt ?? createdAt
        self.trashedAt = trashedAt
        self.formerProjectID = formerProjectID
        self.project = project
    }
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Thought.project) var thoughts: [Thought]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        thoughts = []
    }
}

enum CaptureError: LocalizedError, Equatable {
    case emptyThought
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .emptyThought:
            String(localized: "Enter a Thought before saving.")
        case .couldNotSave:
            String(localized: "Thoughtbox could not save this Thought. Your Draft is still here. Try again.")
        }
    }
}

enum ProjectError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .emptyName:
            String(localized: "Enter a Project name.")
        case let .duplicateName(name):
            String(localized: "A Project named “\(name)” already exists. Project names are compared without regard to capitalization.")
        case .couldNotSave:
            String(localized: "Thoughtbox could not save this Project change. Try again.")
        }
    }
}

enum OrganizationError: LocalizedError, Equatable {
    case bulkMoveFailed

    var errorDescription: String? {
        String(localized: "Thoughtbox could not move the selected Thoughts. Nothing was moved; try again.")
    }
}

enum TrashError: LocalizedError, Equatable {
    case onlyTrashCanBePermanentlyDeleted(count: Int)
    case projectContainsActiveThoughts(count: Int)
    case trashFailed
    case restoreFailed
    case permanentDeletionFailed
    case projectDeletionFailed

    var errorDescription: String? {
        switch self {
        case let .onlyTrashCanBePermanentlyDeleted(count):
            String(localized: "Permanent deletion is only available in Trash. \(count) selected Thought\(count == 1 ? " is" : "s are") still active.")
        case let .projectContainsActiveThoughts(count):
            String(localized: "This Project contains \(count) active Thought\(count == 1 ? "" : "s"). Move or delete \(count == 1 ? "it" : "them") before deleting the Project.")
        case .trashFailed:
            String(localized: "Thoughtbox could not move the selected Thoughts to Trash. Nothing was moved; try again.")
        case .restoreFailed:
            String(localized: "Thoughtbox could not restore the selected Thoughts. Nothing was restored; try again.")
        case .permanentDeletionFailed:
            String(localized: "Thoughtbox could not permanently delete the selected Thoughts. They remain in Trash; try again.")
        case .projectDeletionFailed:
            String(localized: "Thoughtbox could not delete this Project. It was not removed; try again.")
        }
    }
}

struct RestoreResult: Equatable {
    let restoredCount: Int
    let inboxFallbackCount: Int
}

struct ProjectDeletionImpact: Equatable {
    let activeThoughtCount: Int
    let trashedThoughtCount: Int
}

struct ProjectDeletionResult: Equatable {
    let trashedThoughtCount: Int
    let draftDestinationReset: Bool
}

extension String {
    var containsNonWhitespace: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedProjectName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedProjectName: String {
        trimmedProjectName.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
