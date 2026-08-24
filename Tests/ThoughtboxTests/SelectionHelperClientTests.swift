import Foundation
import Testing
@testable import Thoughtbox

@MainActor
struct SelectionHelperClientTests {
    @Test("Selection XPC requests enforce a one-second deadline and clean up")
    func requestTimeout() async {
        #expect(SelectionHelperClient.requestTimeout == .seconds(1))
        var cleanupCount = 0

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                let request = ThrowingXPCRequest<String>(continuation: continuation) {
                    cleanupCount += 1
                }
                request.startTimeout(.milliseconds(10), fallback: .unavailable)
            }
            Issue.record("The timed request unexpectedly succeeded")
        } catch {
            #expect(error as? SelectionCaptureError == .unavailable)
        }
        #expect(cleanupCount == 1)
    }

    @Test("An XPC interruption returns one generic failure and ignores later replies")
    func interruptionIsSingleShot() async {
        var cleanupCount = 0
        var retainedRequest: ThrowingXPCRequest<String>?

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                let request = ThrowingXPCRequest<String>(continuation: continuation) {
                    cleanupCount += 1
                }
                retainedRequest = request
                request.failIfPending()
                request.finish(.success("late sensitive reply"))
            }
            Issue.record("The interrupted request unexpectedly succeeded")
        } catch {
            #expect(error as? SelectionCaptureError == .unavailable)
        }
        #expect(cleanupCount == 1)
        #expect(retainedRequest != nil)
    }
}
