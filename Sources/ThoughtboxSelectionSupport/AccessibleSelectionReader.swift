import ApplicationServices
import Foundation

public struct AccessibilitySelectionSnapshot: Equatable, Sendable {
    public static let secureTextFieldSubrole = "AXSecureTextField"

    public let subrole: String?
    public let selectedText: String?

    public init(subrole: String?, selectedText: String?) {
        self.subrole = subrole
        self.selectedText = selectedText
    }
}

public enum AccessibilitySelectionResult: Equatable, Sendable {
    case selectedText(String)
    case permissionRequired
    case noSelection
}

public protocol AccessibilitySelectionSource: AnyObject {
    func permissionStatus(prompt: Bool) -> Bool
    func focusedSelection() -> AccessibilitySelectionSnapshot?
}

public struct AccessibleSelectionReader {
    private let source: any AccessibilitySelectionSource

    public init(source: any AccessibilitySelectionSource) {
        self.source = source
    }

    public func permissionStatus(prompt: Bool) -> Bool {
        source.permissionStatus(prompt: prompt)
    }

    public func read() -> AccessibilitySelectionResult {
        guard source.permissionStatus(prompt: false) else {
            return .permissionRequired
        }
        guard let snapshot = source.focusedSelection(),
              snapshot.subrole != AccessibilitySelectionSnapshot.secureTextFieldSubrole,
              let text = snapshot.selectedText,
              text.containsNonWhitespace else {
            return .noSelection
        }
        return .selectedText(text)
    }
}

public final class SystemAccessibilitySelectionSource: AccessibilitySelectionSource {
    public init() {}

    public func permissionStatus(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    public func focusedSelection() -> AccessibilitySelectionSnapshot? {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement: AXUIElement = attribute(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWideElement
        ) else {
            return nil
        }

        let subrole: String? = attribute(kAXSubroleAttribute as CFString, from: focusedElement)
        let selectedText: String? = attribute(kAXSelectedTextAttribute as CFString, from: focusedElement)
        return AccessibilitySelectionSnapshot(subrole: subrole, selectedText: selectedText)
    }

    private func attribute<Value>(_ name: CFString, from element: AXUIElement) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value as? Value
    }
}

private extension String {
    var containsNonWhitespace: Bool {
        rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
    }
}
