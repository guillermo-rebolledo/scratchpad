import Foundation
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
            PeerCodeSigningRequirement.forPeer(bundleIdentifier: "com.memoji.Thoughtbox")
        )
        connection.exportedInterface = NSXPCInterface(with: SelectionHelperProtocol.self)
        connection.exportedObject = service
        connection.activate()
        return true
    }
}

private let selectionHelperDelegate = SelectionHelperListenerDelegate()
private let selectionHelperListener = NSXPCListener.service()
selectionHelperListener.delegate = selectionHelperDelegate
selectionHelperListener.resume()
