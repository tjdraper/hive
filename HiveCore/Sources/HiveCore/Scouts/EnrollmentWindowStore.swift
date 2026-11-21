import CryptoKit
import Foundation
import Synchronization

/// Windows for Scouts to enroll through, one for each server, kept in memory only, so restarting Hive
/// closes them. Apart from `PairingWindowStore`, so a window for a server never closes a device's
/// pairing window, nor another server's.
final class EnrollmentWindowStore: Sendable {
    /// Long enough to paste a code into a server's terminal, maybe after installing Scout first.
    static let lifetime: TimeInterval = 15 * 60

    struct Window: Equatable {
        let id: UUID
        let serverID: UUID
        /// The token's hash, so the token itself is never kept.
        let tokenHash: Data
        let expiresAt: Date
        let openedBy: UUID
    }

    enum TokenCheck: Equatable {
        case valid(Window)
        case noWindow
        case expired
        case wrongToken
    }

    private struct Entry {
        let window: Window
        /// Claimed by a Scout that hasn't finished enrolling yet.
        var isClaimed = false
    }

    /// Keyed by server.
    private let entries = Mutex<[UUID: Entry]>([:])

    /// Opens a window for the server, closing any it had, and returns it with its token.
    func open(forServer serverID: UUID, by deviceID: UUID, at now: Date) -> (window: Window, token: Data) {
        let token = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let window = Window(
            id: UUID(),
            serverID: serverID,
            tokenHash: Self.hash(token),
            expiresAt: now.addingTimeInterval(Self.lifetime),
            openedBy: deviceID
        )
        entries.withLock { entries in
            entries = entries.filter { $0.value.isClaimed || now < $0.value.window.expiresAt }
            entries[serverID] = Entry(window: window)
        }
        return (window, token)
    }

    /// True when the server had a window open and it's now closed.
    func close(forServer serverID: UUID, at now: Date) -> Bool {
        entries.withLock { entries in
            guard let entry = entries[serverID], !entry.isClaimed, now < entry.window.expiresAt else { return false }
            entries[serverID] = nil
            return true
        }
    }

    /// Whether `token` opens a window now, without using it up.
    func check(_ token: Data, at now: Date) -> TokenCheck {
        entries.withLock { Self.check(token, against: $0, at: now) }
    }

    /// Takes the window for one Scout, so its token never works again. Nil when `token` doesn't open
    /// one, such as when another Scout took it first.
    func claim(_ token: Data, at now: Date) -> Window? {
        entries.withLock { entries in
            guard case .valid(let window) = Self.check(token, against: entries, at: now) else { return nil }
            entries[window.serverID]?.isClaimed = true
            return window
        }
    }

    /// The claimed window was used, or couldn't be, and is closed rather than reopened.
    func finish(_ window: Window) {
        entries.withLock { entries in
            guard entries[window.serverID]?.window.id == window.id else { return }
            entries[window.serverID] = nil
        }
    }

    private static func check(_ token: Data, against entries: [UUID: Entry], at now: Date) -> TokenCheck {
        let hash = hash(token)
        guard let entry = entries.values.first(where: { $0.window.tokenHash == hash }) else {
            let anyOpen = entries.values.contains { !$0.isClaimed && now < $0.window.expiresAt }
            return anyOpen ? .wrongToken : .noWindow
        }
        guard !entry.isClaimed else { return .noWindow }
        guard now < entry.window.expiresAt else { return .expired }
        return .valid(entry.window)
    }

    private static func hash(_ token: Data) -> Data {
        Data(SHA256.hash(data: token))
    }
}
