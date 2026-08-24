import Foundation

enum SelectionFailurePresentationStyle: Equatable, Sendable {
    case alert
    case toast
}

struct SelectionFailurePresentation: Equatable, Sendable {
    let style: SelectionFailurePresentationStyle
    let message: String
    let offersAccessibilitySettings: Bool
}

@MainActor
final class SelectionFailurePresenter {
    static let permissionAlertShownKey = "selectionCapture.permissionAlertShown"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func presentation(for error: SelectionCaptureError) -> SelectionFailurePresentation {
        switch error {
        case .permissionRequired:
            let shouldShowAlert = !defaults.bool(forKey: Self.permissionAlertShownKey)
            if shouldShowAlert { defaults.set(true, forKey: Self.permissionAlertShownKey) }
            return SelectionFailurePresentation(
                style: shouldShowAlert ? .alert : .toast,
                message: String(
                    localized: "selectionCapture.permissionRequired",
                    defaultValue: "Accessibility permission is required to capture selected text."
                ),
                offersAccessibilitySettings: true
            )
        case .noSelection:
            return toast(String(
                localized: "selectionCapture.noSelection",
                defaultValue: "No selected text was available."
            ))
        case .tooLarge:
            return toast(String(
                localized: "selectionCapture.tooLarge",
                defaultValue: "The Draft and selected text must be 50,000 characters or fewer."
            ))
        case .unavailable:
            return toast(String(
                localized: "selectionCapture.unavailable",
                defaultValue: "Thoughtbox could not capture the selected text."
            ))
        }
    }

    private func toast(_ message: String) -> SelectionFailurePresentation {
        SelectionFailurePresentation(
            style: .toast,
            message: message,
            offersAccessibilitySettings: false
        )
    }
}
