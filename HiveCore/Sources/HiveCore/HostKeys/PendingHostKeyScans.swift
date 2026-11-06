import Foundation
import HiveKit
import Synchronization

/// The key each server's last scan found, kept in memory until a device confirms it. Only a key Hive
/// scanned itself can be recorded, for the connection it was scanned on. A restart forgets them, and
/// scanning again starts over.
final class PendingHostKeyScans: Sendable {
    /// Long enough to log in to the server and compare the fingerprint.
    static let lifetime: TimeInterval = 15 * 60

    struct Scan: Equatable {
        let connection: ServerConnection
        let key: OpenSSHPublicKey
        let scannedAt: Date
    }

    private let scans = Mutex<[UUID: Scan]>([:])

    func record(_ key: OpenSSHPublicKey, forServer id: UUID, connection: ServerConnection, at date: Date) {
        scans.withLock { $0[id] = Scan(connection: connection, key: key, scannedAt: date) }
    }

    /// Nil when there's none, or it's too old.
    func scan(forServer id: UUID, at date: Date) -> Scan? {
        scans.withLock { scans in
            guard let scan = scans[id] else { return nil }
            guard date.timeIntervalSince(scan.scannedAt) <= Self.lifetime, date >= scan.scannedAt else {
                scans[id] = nil
                return nil
            }
            return scan
        }
    }

    func remove(forServer id: UUID) {
        scans.withLock { $0[id] = nil }
    }
}
