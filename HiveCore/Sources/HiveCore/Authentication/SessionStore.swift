import CryptoKit
import Foundation
import Synchronization

/// Who a session belongs to. A Scout's session is for one server, and reaches only Scout's routes.
enum SessionOwner: Hashable, Sendable {
    case device(UUID)
    case scout(SignedInScout)
}

struct SignedInScout: Hashable, Sendable {
    let scoutID: UUID
    let serverID: UUID
}

/// Signed-in sessions, kept in memory only, so restarting the daemon signs every device and Scout out.
public final class SessionStore: Sendable {
    /// Short, so a token that leaks is soon useless. Beekeeper and Scout sign in again when one runs out.
    static let lifetime: TimeInterval = 15 * 60

    private struct Session {
        let owner: SessionOwner
        let expiresAt: Date
    }

    /// Keyed by the token's hash, so the tokens themselves are never kept.
    private let sessions = Mutex<[Data: Session]>([:])

    public init() {}

    func start(for deviceID: UUID, at now: Date) -> (token: String, expiresAt: Date) {
        start(for: .device(deviceID), at: now)
    }

    func start(for owner: SessionOwner, at now: Date) -> (token: String, expiresAt: Date) {
        let token = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64URLEncoded
        let expiresAt = now.addingTimeInterval(Self.lifetime)
        sessions.withLock { sessions in
            sessions = sessions.filter { $0.value.expiresAt > now }
            sessions[Self.hash(token)] = Session(owner: owner, expiresAt: expiresAt)
        }
        return (token, expiresAt)
    }

    /// Who the session is for, or nil when the token is unknown or has expired.
    func owner(forToken token: String, at now: Date) -> SessionOwner? {
        sessions.withLock { sessions in
            guard let session = sessions[Self.hash(token)], now < session.expiresAt else { return nil }
            return session.owner
        }
    }

    /// The signed-in device, or nil when the token is unknown, has expired or is a Scout's.
    func deviceID(forToken token: String, at now: Date) -> UUID? {
        guard case .device(let deviceID) = owner(forToken: token, at: now) else { return nil }
        return deviceID
    }

    public func endSessions(for deviceID: UUID) {
        sessions.withLock { sessions in
            sessions = sessions.filter { $0.value.owner != .device(deviceID) }
        }
    }

    /// Ends the sessions of every Scout that reported for the server, such as when its Scout is removed
    /// or replaced.
    func endScoutSessions(forServer serverID: UUID) {
        sessions.withLock { sessions in
            sessions = sessions.filter { session in
                guard case .scout(let scout) = session.value.owner else { return true }
                return scout.serverID != serverID
            }
        }
    }

    func endAllSessions() {
        sessions.withLock { $0 = [:] }
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
