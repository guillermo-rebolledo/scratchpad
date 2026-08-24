import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct SelectionFailurePresentationTests {
    @Test("Accessibility permission uses one alert, then actionable toasts")
    func permissionOnboardingIsShownOnce() throws {
        let suite = "ThoughtboxSelectionFailureTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let presenter = SelectionFailurePresenter(defaults: defaults)

        let first = presenter.presentation(for: .permissionRequired)
        #expect(first.style == .alert)
        #expect(first.offersAccessibilitySettings)
        #expect(first.message.contains("Accessibility"))

        let second = presenter.presentation(for: .permissionRequired)
        #expect(second.style == .toast)
        #expect(second.offersAccessibilitySettings)

        let relaunched = SelectionFailurePresenter(defaults: defaults)
        #expect(relaunched.presentation(for: .permissionRequired).style == .toast)
    }

    @Test("Selection failures have generic, non-sensitive toast copy")
    func genericFailureCopy() {
        let defaults = UserDefaults(suiteName: "ThoughtboxSelectionCopyTests-\(UUID().uuidString)")!
        let presenter = SelectionFailurePresenter(defaults: defaults)

        let noSelection = presenter.presentation(for: .noSelection)
        #expect(noSelection.style == .toast)
        #expect(noSelection.offersAccessibilitySettings == false)
        #expect(noSelection.message == "No selected text was available.")

        let tooLarge = presenter.presentation(for: .tooLarge)
        #expect(tooLarge.style == .toast)
        #expect(tooLarge.message.contains("50,000"))

        let unavailable = presenter.presentation(for: .unavailable)
        #expect(unavailable.style == .toast)
        #expect(unavailable.message == "Thoughtbox could not capture the selected text.")
    }
}
