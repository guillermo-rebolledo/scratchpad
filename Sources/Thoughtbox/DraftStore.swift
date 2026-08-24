import Foundation
import Observation

enum SelectionCaptureError: Error, Equatable, Sendable {
    case permissionRequired
    case noSelection
    case tooLarge
    case unavailable
}

@MainActor
@Observable
final class DraftStore {
    static let maximumSelectionDraftCharacters = 50_000

    private enum Key {
        static let markdown = "draft.markdown"
        static let projectID = "draft.projectID"
    }

    private let defaults: UserDefaults

    var markdown: String {
        didSet { defaults.set(markdown, forKey: Key.markdown) }
    }

    var projectID: UUID? {
        didSet {
            if let projectID {
                defaults.set(projectID.uuidString, forKey: Key.projectID)
            } else {
                defaults.removeObject(forKey: Key.projectID)
            }
        }
    }

    var destinationNotice: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        markdown = defaults.string(forKey: Key.markdown) ?? ""
        projectID = defaults.string(forKey: Key.projectID).flatMap(UUID.init(uuidString:))
        destinationNotice = nil
    }

    var canSave: Bool {
        markdown.containsNonWhitespace
    }

    func prepareForCapture(in projectID: UUID?) {
        self.projectID = projectID
        destinationNotice = nil
    }

    func addSelectedText(_ text: String) throws {
        let selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { throw SelectionCaptureError.noSelection }

        let candidate = markdown.isEmpty ? selection : markdown + "\n\n" + selection
        guard candidate.count <= Self.maximumSelectionDraftCharacters else {
            throw SelectionCaptureError.tooLarge
        }

        markdown = candidate
    }

    func clear() {
        markdown = ""
        projectID = nil
        destinationNotice = nil
    }

    func fallBackToInboxBecauseProjectIsUnavailable() {
        projectID = nil
        destinationNotice = String(localized: "The selected Project no longer exists. Your Draft is intact and will save to Inbox.")
    }
}
