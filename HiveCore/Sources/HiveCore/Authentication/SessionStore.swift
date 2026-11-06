import CryptoKit
import Foundation
import Synchronization

/// Signed-in sessions, kept in memory only, so restarting the daemon signs every device out.
public final class SessionStore: Sendable {
    /// Short, so a token that leaks is soon useless. Beekeeper signs in again when one runs out.
    static let lifetime: TimeInterval = 15 * 60

    private struct Session {
        let deviceID: UUID
        let expiresAt: Date
    }

    /// Keyed by the token's hash, so the tokens themselves are never kept.
    private let sessions = Mutex<[Data: Session]>([:])

    public init() {}

    func start(for deviceID: UUID, at now: Date) -> (token: String, expiresAt: Date) {
        let token = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64URLEncoded
        let expiresAt = now.addingTimeInterval(Self.lifetime)
        sessions.withLock { sessions in
            sessions = sessions.filter { $0.value.expiresAt > now }
            sessions[Self.hash(token)] = Session(deviceID: deviceID, expiresAt: expiresAt)
        }
        return (token, expiresAt)
    }

    /// The signed-in device, or nil when the token is unknown or has expired.
    func deviceID(forToken token: String, at now: Date) -> UUID? {
        sessions.withLock { sessions in
            guard let session = sessions[Self.hash(token)], now < session.expiresAt else { return nil }
            return session.deviceID
        }
    }

    public func endSessions(for deviceID: UUID) {
        sessions.withLock { sessions in
            sessions = sessions.filter { $0.value.deviceID != deviceID }
        }
    }

    private static func hash(_ token: String) -> Data {
        Data(SHA256.hash(data: Data(token.utf8)))
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
