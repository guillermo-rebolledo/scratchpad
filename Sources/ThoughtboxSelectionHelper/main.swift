import Foundation
import Security
#if canImport(ThoughtboxSelectionSupport)
import ThoughtboxSelectionSupport
#endif

@objc(ThoughtboxSelectionHelperProtocol)
private protocol SelectionHelperProtocol {
    func accessibilityPermissionStatus(prompt: Bool, reply: @escaping (Bool) -> Void)
    func selectedText(reply: @escaping (String?, String?) -> Void)
}

private enum SelectionHelperReplyCode {
    static let permissionRequired = "permissionRequired"
    static let noSelection = "noSelection"
}

private final class SelectionHelperService: NSObject, SelectionHelperProtocol {
    private let reader = AccessibleSelectionReader(source: SystemAccessibilitySelectionSource())

    func accessibilityPermissionStatus(prompt: Bool, reply: @escaping (Bool) -> Void) {
        reply(reader.permissionStatus(prompt: prompt))
    }

    func selectedText(reply: @escaping (String?, String?) -> Void) {
        switch reader.read() {
        case let .selectedText(text):
            reply(text, nil)
        case .permissionRequired:
            reply(nil, SelectionHelperReplyCode.permissionRequired)
        case .noSelection:
            reply(nil, SelectionHelperReplyCode.noSelection)
        }
    }
}

private final class SelectionHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = SelectionHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(
            PeerCodeSigning.requirement(bundleIdentifier: "com.memoji.Thoughtbox")
        )
        connection.exportedInterface = NSXPCInterface(with: SelectionHelperProtocol.self)
        connection.exportedObject = service
        connection.activate()
        return true
    }
}

private enum PeerCodeSigning {
    static func requirement(bundleIdentifier: String) -> String {
        guard let teamIdentifier else {
            return "identifier \"\(bundleIdentifier)\""
        }
        return "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    private static var teamIdentifier: String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [CFString: Any] else {
            return nil
        }
        return values[kSecCodeInfoTeamIdentifier] as? String
    }
}

private let selectionHelperDelegate = SelectionHelperListenerDelegate()
private let selectionHelperListener = NSXPCListener.service()
selectionHelperListener.delegate = selectionHelperDelegate
selectionHelperListener.resume()
