import Foundation
import Testing
import ThoughtboxSelectionSupport

struct SelectionHelperCoreTests {
    @Test("Selection reader returns only eligible selected text")
    func readsSelectedText() {
        let source = TestAccessibilitySelectionSource(
            trusted: true,
            snapshot: AccessibilitySelectionSnapshot(
                subrole: "AXTextArea",
                selectedText: "Selected **Markdown**"
            )
        )

        #expect(AccessibleSelectionReader(source: source).read() == .selectedText("Selected **Markdown**"))
    }

    @Test("Selection reader rejects untrusted, secure, and empty sources")
    func rejectsProtectedOrUnavailableSelections() {
        let untrusted = TestAccessibilitySelectionSource(trusted: false, snapshot: nil)
        #expect(AccessibleSelectionReader(source: untrusted).read() == .permissionRequired)

        let secure = TestAccessibilitySelectionSource(
            trusted: true,
            snapshot: AccessibilitySelectionSnapshot(
                subrole: AccessibilitySelectionSnapshot.secureTextFieldSubrole,
                selectedText: "secret"
            )
        )
        #expect(AccessibleSelectionReader(source: secure).read() == .noSelection)

        let whitespace = TestAccessibilitySelectionSource(
            trusted: true,
            snapshot: AccessibilitySelectionSnapshot(subrole: "AXTextArea", selectedText: " \n\t ")
        )
        #expect(AccessibleSelectionReader(source: whitespace).read() == .noSelection)
    }

    @Test("Permission prompting remains an explicit caller decision")
    func permissionPromptIsExplicit() {
        let source = TestAccessibilitySelectionSource(trusted: false, snapshot: nil)
        let reader = AccessibleSelectionReader(source: source)

        #expect(reader.permissionStatus(prompt: false) == false)
        #expect(reader.permissionStatus(prompt: true) == false)
        #expect(source.prompts == [false, true])
    }
}

private final class TestAccessibilitySelectionSource: AccessibilitySelectionSource {
    let trusted: Bool
    let snapshot: AccessibilitySelectionSnapshot?
    private(set) var prompts: [Bool] = []

    init(trusted: Bool, snapshot: AccessibilitySelectionSnapshot?) {
        self.trusted = trusted
        self.snapshot = snapshot
    }

    func permissionStatus(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return trusted
    }

    func focusedSelection() -> AccessibilitySelectionSnapshot? {
        snapshot
    }
}
