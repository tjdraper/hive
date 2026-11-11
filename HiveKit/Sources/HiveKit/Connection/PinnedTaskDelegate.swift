import Foundation
import Synchronization

/// Checks the pin for one request. Each request gets its own, so a key refused at one address, such as
/// another machine that has the Hive's old LAN address, says nothing about requests to the others.
/// URLSession asks a task's delegate about the server's trust only because the session has no delegate.
final class PinnedTaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let evaluator: PinnedTrustEvaluator
    private let refused = Mutex(false)

    /// Whether the server showed a key other than the pinned one.
    var refusedKey: Bool {
        refused.withLock { $0 }
    }

    init(pin: PublicKeyPin) {
        evaluator = PinnedTrustEvaluator(pin: pin)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard evaluator.accepts(trust) else {
            refused.withLock { $0 = true }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
