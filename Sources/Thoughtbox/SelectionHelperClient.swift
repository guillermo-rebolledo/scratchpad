import Foundation
import Security

@objc(ThoughtboxSelectionHelperProtocol)
private protocol SelectionHelperProtocol {
    func accessibilityPermissionStatus(prompt: Bool, reply: @escaping (Bool) -> Void)
    func selectedText(reply: @escaping (String?, String?) -> Void)
}

private enum SelectionHelperReplyCode {
    static let permissionRequired = "permissionRequired"
    static let noSelection = "noSelection"
}

@MainActor
final class SelectionHelperClient: SelectionProviding {
    static let serviceName = "com.memoji.Thoughtbox.SelectionHelper"
    private static let timeout: Duration = .seconds(1)

    func selectedText() async throws -> String {
        let connection = makeConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let request = ThrowingXPCRequest(continuation: continuation, connection: connection)
            configureFailureHandlers(for: connection, request: request)
            connection.activate()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                Task { @MainActor in request.finish(.failure(SelectionCaptureError.unavailable)) }
            }) as? SelectionHelperProtocol else {
                request.finish(.failure(SelectionCaptureError.unavailable))
                return
            }
            proxy.selectedText { text, replyCode in
                Task { @MainActor in
                    if let text {
                        request.finish(.success(text))
                    } else if replyCode == SelectionHelperReplyCode.permissionRequired {
                        request.finish(.failure(SelectionCaptureError.permissionRequired))
                    } else if replyCode == SelectionHelperReplyCode.noSelection {
                        request.finish(.failure(SelectionCaptureError.noSelection))
                    } else {
                        request.finish(.failure(SelectionCaptureError.unavailable))
                    }
                }
            }
            request.startTimeout(Self.timeout, fallback: .unavailable)
        }
    }

    func accessibilityPermissionStatus(prompt: Bool) async -> Bool {
        let connection = makeConnection()
        return await withCheckedContinuation { continuation in
            let request = ValueXPCRequest(continuation: continuation, connection: connection, fallback: false)
            configureFailureHandlers(for: connection, request: request)
            connection.activate()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                Task { @MainActor in request.finish(false) }
            }) as? SelectionHelperProtocol else {
                request.finish(false)
                return
            }
            proxy.accessibilityPermissionStatus(prompt: prompt) { granted in
                Task { @MainActor in request.finish(granted) }
            }
            request.startTimeout(Self.timeout, fallback: false)
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(serviceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: SelectionHelperProtocol.self)
        connection.setCodeSigningRequirement(
            PeerCodeSigning.requirement(bundleIdentifier: Self.serviceName)
        )
        return connection
    }

    private func configureFailureHandlers<Value: Sendable>(
        for connection: NSXPCConnection,
        request: ThrowingXPCRequest<Value>
    ) {
        connection.interruptionHandler = {
            Task { @MainActor in request.failIfPending() }
        }
        connection.invalidationHandler = {
            Task { @MainActor in request.failIfPending() }
        }
    }

    private func configureFailureHandlers<Value: Sendable>(
        for connection: NSXPCConnection,
        request: ValueXPCRequest<Value>
    ) {
        connection.interruptionHandler = {
            Task { @MainActor in request.failIfPending() }
        }
        connection.invalidationHandler = {
            Task { @MainActor in request.failIfPending() }
        }
    }
}

@MainActor
private final class ThrowingXPCRequest<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private let connection: NSXPCConnection

    init(
        continuation: CheckedContinuation<Value, any Error>,
        connection: NSXPCConnection
    ) {
        self.continuation = continuation
        self.connection = connection
    }

    func startTimeout(_ duration: Duration, fallback: SelectionCaptureError) where Value == String {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            self?.finish(.failure(fallback))
        }
    }

    func failIfPending() {
        finish(.failure(SelectionCaptureError.unavailable))
    }

    func finish(_ result: sending Result<Value, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
        continuation.resume(with: result)
    }
}

@MainActor
private final class ValueXPCRequest<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private let connection: NSXPCConnection
    private let fallback: Value

    init(
        continuation: CheckedContinuation<Value, Never>,
        connection: NSXPCConnection,
        fallback: Value
    ) {
        self.continuation = continuation
        self.connection = connection
        self.fallback = fallback
    }

    func startTimeout(_ duration: Duration, fallback: Value) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            self?.finish(fallback)
        }
    }

    func failIfPending() {
        finish(fallback)
    }

    func finish(_ value: sending Value) {
        guard let continuation else { return }
        self.continuation = nil
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
        continuation.resume(returning: value)
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

@MainActor
final class UITestSelectionProvider: SelectionProviding {
    private let processInfo: ProcessInfo

    init(processInfo: ProcessInfo = .processInfo) {
        self.processInfo = processInfo
    }

    func selectedText() async throws -> String {
        if processInfo.arguments.contains("--simulate-selection-permission-required") {
            throw SelectionCaptureError.permissionRequired
        }
        if processInfo.arguments.contains("--simulate-selection-unavailable") {
            throw SelectionCaptureError.unavailable
        }
        guard let text = processInfo.environment["THOUGHTBOX_UI_SELECTED_TEXT"] else {
            throw SelectionCaptureError.noSelection
        }
        return text
    }

    func accessibilityPermissionStatus(prompt: Bool) async -> Bool {
        !processInfo.arguments.contains("--simulate-selection-permission-required")
    }
}
