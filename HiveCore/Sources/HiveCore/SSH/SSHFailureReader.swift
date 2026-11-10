import Foundation
import HiveKit

/// Tells apart why `ssh` failed from what it wrote. It exits with 255 for its own errors, and
/// otherwise with the remote command's status.
enum SSHFailureReader {
    static let sshErrorStatus: Int32 = 255

    private static let hostKeyMessages = ["REMOTE HOST IDENTIFICATION HAS CHANGED", "Host key verification failed", "host key is known for"]
    private static let loginMessages = ["Permission denied", "Too many authentication failures"]
    private static let stallMessages = ["Timeout, server", "not responding"]
    private static let unreachableMessages = [
        "Could not resolve hostname",
        "Connection refused",
        "Operation timed out",
        "Connection timed out",
        "No route to host",
        "Network is unreachable",
        "Host is down",
        "Connection closed by",
        "Connection reset by",
        "kex_exchange_identification",
    ]

    /// Nil when it succeeded.
    static func failure(in result: ChildProcess.Result) -> ConnectionFailure? {
        guard result.status != 0 else { return nil }
        guard result.status == sshErrorStatus else { return .failed }
        return recognizedFailure(in: result.standardError) ?? .failed
    }

    /// The failure ssh's own messages in `standardError` describe, or nil when there are none.
    static func recognizedFailure(in standardError: Data) -> ConnectionFailure? {
        let output = String(bytes: standardError, encoding: .utf8) ?? ""
        // The changed key comes first: its warning can hold words the others look for.
        if containsAny(hostKeyMessages, in: output) { return .hostKeyChanged }
        if containsAny(loginMessages, in: output) { return .loginRefused }
        if containsAny(stallMessages, in: output) { return .stalled }
        if containsAny(unreachableMessages, in: output) { return .unreachable }
        return nil
    }

    private static func containsAny(_ messages: [String], in output: String) -> Bool {
        messages.contains { output.contains($0) }
    }
}
