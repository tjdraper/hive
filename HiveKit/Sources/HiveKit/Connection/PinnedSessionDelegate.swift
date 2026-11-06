import Foundation
import Synchronization

final class PinnedSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    private let evaluator: PinnedTrustEvaluator
    private let refused = Mutex(false)

    /// Whether a server has shown a key other than the pinned one.
    var refusedKey: Bool {
        refused.withLock { $0 }
    }

    init(pin: PublicKeyPin) {
        evaluator = PinnedTrustEvaluator(pin: pin)
    }

    func urlSession(
        _: URLSession,
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
