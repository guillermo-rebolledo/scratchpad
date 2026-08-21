import Foundation
import SwiftData

@Model
final class Thought {
    @Attribute(.unique) var id: UUID
    var markdown: String
    var createdAt: Date
    var editedAt: Date
    var trashedAt: Date?
    var project: Project?

    init(
        id: UUID = UUID(),
        markdown: String,
        createdAt: Date = .now,
        editedAt: Date? = nil,
        trashedAt: Date? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.markdown = markdown
        self.createdAt = createdAt
        self.editedAt = editedAt ?? createdAt
        self.trashedAt = trashedAt
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
            "Enter a Thought before saving."
        case .couldNotSave:
            "Thoughtbox could not save this Thought. Your Draft is still here. Try again."
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
            "Enter a Project name."
        case let .duplicateName(name):
            "A Project named “\(name)” already exists. Project names are compared without regard to capitalization."
        case .couldNotSave:
            "Thoughtbox could not save this Project change. Try again."
        }
    }
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
