import Foundation
import Observation

@MainActor
@Observable
final class DraftStore {
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
