import AppKit
import Carbon
import Sparkle
import SwiftData

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let container: ModelContainer
    let draft: DraftStore
    let settings: SettingsModel
    let updaterController: SPUStandardUpdaterController
    private(set) var captureController: CaptureController?
    private(set) var shortcutManager: GlobalShortcutManager?
    private var selectionCaptureCoordinator: SelectionCaptureCoordinator?
    private let selectionProvider: SelectionProviding
    private let selectionFailurePresenter: SelectionFailurePresenter

    private init() {
        let processInfo = ProcessInfo.processInfo
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !processInfo.arguments.contains("--ui-testing"),
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        do {
            container = try PersistenceFactory.makeContainer()
        } catch {
            fatalError("Thoughtbox could not open its local store: \(error.localizedDescription)")
        }
        let defaults = PersistenceFactory.makeDraftDefaults()
        draft = DraftStore(defaults: defaults)
        selectionProvider = processInfo.arguments.contains("--ui-testing")
            ? UITestSelectionProvider(processInfo: processInfo)
            : SelectionHelperClient()
        selectionFailurePresenter = SelectionFailurePresenter(defaults: defaults)
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
        let coordinator = SelectionCaptureCoordinator(
            draft: draft,
            provider: selectionProvider,
            onSuccess: { [weak controller] in controller?.showCaptureWithSelection() },
            onFailure: { [weak self, weak controller] error in
                guard let self else { return }
                let presentation = self.selectionFailurePresenter.presentation(for: error)
                controller?.presentSelectionFailure(presentation) { [weak self] in
                    self?.requestSelectionPermissionAndOpenSettings()
                }
            }
        )
        selectionCaptureCoordinator = coordinator
        let manager = GlobalShortcutManager(
            quickCapture: { [weak controller] in controller?.showCapture() },
            captureSelection: { [weak coordinator] in
                Task { @MainActor in await coordinator?.captureSelection() }
            }
        )
        shortcutManager = manager
        settings.connectShortcutRegistration { shortcut in
            if ProcessInfo.processInfo.arguments.contains("--simulate-shortcut-conflict"),
               shortcut.keyCode == UInt32(kVK_ANSI_K),
               shortcut.modifiers == [.control, .option] {
                throw GlobalShortcutError.unavailable
            }
            try manager.register(shortcut)
        }
        settings.connectSelectionShortcutRegistration { shortcut in
            if ProcessInfo.processInfo.arguments.contains("--simulate-selection-shortcut-conflict") {
                throw GlobalShortcutError.unavailable
            }
            try manager.register(shortcut, for: .captureSelection)
        }
        settings.connectSelectionPermissionStatus { [weak selectionProvider] prompt in
            await selectionProvider?.accessibilityPermissionStatus(prompt: prompt) ?? false
        }
    }

    func showCapture() {
        captureController?.showCapture()
    }

    private func requestSelectionPermissionAndOpenSettings() {
        Task { @MainActor [weak self] in
            _ = await self?.selectionProvider.accessibilityPermissionStatus(prompt: true)
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
