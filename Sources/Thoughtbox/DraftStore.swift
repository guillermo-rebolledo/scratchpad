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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        markdown = defaults.string(forKey: Key.markdown) ?? ""
        projectID = defaults.string(forKey: Key.projectID).flatMap(UUID.init(uuidString:))
    }

    var canSave: Bool {
        !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clear() {
        markdown = ""
        projectID = nil
    }
}

