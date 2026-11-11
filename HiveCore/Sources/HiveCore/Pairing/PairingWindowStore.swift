import CryptoKit
import Foundation
import HiveKit
import Synchronization

/// The one pairing window, kept in memory only, so restarting Hive closes it. Opening one replaces any
/// that's open, so there's never more than one token that works.
final class PairingWindowStore: Sendable {
    /// Long enough to get a code from one device to another, short enough that a code seen over a
    /// shoulder or left in a message is soon useless.
    static let lifetime: TimeInterval = 5 * 60

    struct Window: Equatable {
        let id: UUID
        /// The token's hash, so the token itself is never kept.
        let tokenHash: Data
        let expiresAt: Date
        let openedBy: UUID
        let openedByName: String
    }

    enum TokenCheck: Equatable {
        case valid(Window)
        case noWindow
        case expired
        case wrongToken
    }

    private enum Latest {
        case closed
        case open(Window)
        /// Claimed by a device that hasn't finished pairing yet.
        case claimed(Window)
        case used(id: UUID, deviceID: UUID, deviceName: String)
    }

    private let latest = Mutex(Latest.closed)

    /// Opens a new window, closing any that's open, and returns it with its token.
    func open(by deviceID: UUID, named deviceName: String, at now: Date) -> (window: Window, token: Data) {
        let token = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let window = Window(
            id: UUID(),
            tokenHash: Self.hash(token),
            expiresAt: now.addingTimeInterval(Self.lifetime),
            openedBy: deviceID,
            openedByName: deviceName
        )
        latest.withLock { $0 = .open(window) }
        return (window, token)
    }

    /// True when a window was open and is now closed.
    func close(at now: Date) -> Bool {
        latest.withLock { latest in
            guard case .open(let window) = latest, now < window.expiresAt else { return false }
            latest = .closed
            return true
        }
    }

    func state(at now: Date) -> PairingWindowState {
        latest.withLock { latest in
            switch latest {
            case .open(let window) where now < window.expiresAt:
                .open(id: window.id, expiresInSeconds: Int(window.expiresAt.timeIntervalSince(now).rounded(.up)))
            case .used(let id, let deviceID, let deviceName):
                .used(id: id, deviceID: deviceID, deviceName: deviceName)
            case .open, .claimed, .closed:
                .closed
            }
        }
    }

    /// Whether `token` opens the window now, without using it up.
    func check(_ token: Data, at now: Date) -> TokenCheck {
        latest.withLock { Self.check(token, against: $0, at: now) }
    }

    /// Takes the window for one device, so its token never works again. Nil when `token` doesn't open it,
    /// such as when another device took it first.
    func claim(_ token: Data, at now: Date) -> Window? {
        latest.withLock { latest in
            guard case .valid(let window) = Self.check(token, against: latest, at: now) else { return nil }
            latest = .claimed(window)
            return window
        }
    }

    /// The claimed window was used, so the device that opened it can show who paired.
    func finish(_ window: Window, pairing device: PairedDevice) {
        latest.withLock { latest in
            guard case .claimed(let claimed) = latest, claimed.id == window.id else { return }
            latest = .used(id: window.id, deviceID: device.id, deviceName: device.name)
        }
    }

    /// The claimed window couldn't be used, and is closed rather than reopened.
    func abandon(_ window: Window) {
        latest.withLock { latest in
            guard case .claimed(let claimed) = latest, claimed.id == window.id else { return }
            latest = .closed
        }
    }

    private static func check(_ token: Data, against latest: Latest, at now: Date) -> TokenCheck {
        guard case .open(let window) = latest else { return .noWindow }
        guard now < window.expiresAt else { return .expired }
        return hash(token) == window.tokenHash ? .valid(window) : .wrongToken
    }

    private static func hash(_ token: Data) -> Data {
        Data(SHA256.hash(data: token))
    }
}
