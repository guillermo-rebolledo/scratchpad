import Foundation
import SwiftData

@Model
final class Thought {
    @Attribute(.unique) var id: UUID
    var markdown: String
    var createdAt: Date
    var editedAt: Date

    init(
        id: UUID = UUID(),
        markdown: String,
        createdAt: Date = .now,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.markdown = markdown
        self.createdAt = createdAt
        self.editedAt = editedAt ?? createdAt
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

