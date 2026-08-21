import AppKit
import Carbon
import SwiftData

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let container: ModelContainer
    let draft: DraftStore
    let settings: SettingsModel
    private(set) var captureController: CaptureController?
    private(set) var shortcutManager: GlobalShortcutManager?

    private init() {
        do {
            container = try PersistenceFactory.makeContainer()
        } catch {
            fatalError("Thoughtbox could not open its local store: \(error.localizedDescription)")
        }
        let defaults = PersistenceFactory.makeDraftDefaults()
        draft = DraftStore(defaults: defaults)
        let processInfo = ProcessInfo.processInfo
        let loginItemService: LoginItemServicing = processInfo.arguments.contains("--ui-testing")
            ? UITestLoginItemService(
                defaults: defaults,
                shouldFail: processInfo.arguments.contains("--simulate-login-item-failure")
            )
            : SystemLoginItemService()
        settings = SettingsModel(defaults: defaults, loginItemService: loginItemService)
    }

    func startCaptureServices() {
        guard captureController == nil else { return }
        let controller = CaptureController(container: container, draft: draft)
        captureController = controller
        let manager = GlobalShortcutManager { [weak controller] in
            controller?.showCapture()
        }
        shortcutManager = manager
        settings.connectShortcutRegistration { shortcut in
            if ProcessInfo.processInfo.arguments.contains("--simulate-shortcut-conflict"),
               shortcut.keyCode == UInt32(kVK_ANSI_K),
               shortcut.modifiers == [.control, .option] {
                throw GlobalShortcutError.unavailable
            }
            try manager.register(shortcut)
        }
    }

    func showCapture() {
        captureController?.showCapture()
    }
}
