import AppKit
import SwiftData

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let container: ModelContainer
    let draft: DraftStore
    private(set) var captureController: CaptureController?
    private(set) var shortcutManager: GlobalShortcutManager?

    private init() {
        do {
            container = try PersistenceFactory.makeContainer()
        } catch {
            fatalError("Thoughtbox could not open its local store: \(error.localizedDescription)")
        }
        draft = DraftStore(defaults: PersistenceFactory.makeDraftDefaults())
    }

    func startCaptureServices() {
        guard captureController == nil else { return }
        let controller = CaptureController(container: container, draft: draft)
        captureController = controller
        shortcutManager = GlobalShortcutManager { [weak controller] in
            controller?.showCapture()
        }
    }

    func showCapture() {
        captureController?.showCapture()
    }
}

