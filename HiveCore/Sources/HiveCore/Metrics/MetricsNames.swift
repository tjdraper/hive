import Foundation
import GRDB
import ScoutProtocol

/// The filesystems, disks and interfaces a server reports, each with an ID its figures are kept under.
/// A server can bring in only so many new ones a day (§2), so one that's been taken over can't fill the
/// store with names.
struct MetricsNames {
    private struct Key: Hashable {
        let kind: String
        let name: String
    }

    private let serverKey: Int64
    private var ids: [Key: Int64]

    init(serverKey: Int64, in database: Database) throws {
        self.serverKey = serverKey
        let rows = try Row.fetchAll(database, sql: "SELECT id, kind, name FROM metricsName WHERE serverKey = ?", arguments: [serverKey])
        ids = Dictionary(uniqueKeysWithValues: rows.map { row -> (Key, Int64) in (Key(kind: row["kind"], name: row["name"]), row["id"]) })
    }

    /// Records the report's new names, or returns false, recording nothing, when they'd take the
    /// server over its day's limit.
    mutating func admit(_ report: MetricsReport, at now: Date, in database: Database) throws -> Bool {
        let figures = report.samples.map { ($0.filesystems, $0.disks, $0.networkInterfaces) }
            + report.minutes.map { ($0.average.filesystems, $0.average.disks, $0.average.networkInterfaces) }
        // With a filesystem's device and type.
        var new: [Key: (device: String?, type: String?)] = [:]
        func add(_ kind: String, _ name: String, device: String? = nil, type: String? = nil) {
            let key = Key(kind: kind, name: name)
            if ids[key] == nil { new[key] = (device, type) }
        }
        for (filesystems, disks, interfaces) in figures {
            for filesystem in filesystems {
                add(MetricsTables.filesystemKind, filesystem.mountPoint, device: filesystem.device, type: filesystem.type)
            }
            for disk in disks { add(MetricsTables.diskKind, disk.name) }
            for interface in interfaces { add(MetricsTables.networkInterfaceKind, interface.name) }
        }
        guard !new.isEmpty else { return true }

        let recent = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM metricsName WHERE serverKey = ? AND firstSeenAt > ?",
            arguments: [serverKey, now.addingTimeInterval(-86_400)]
        ) ?? 0
        guard recent + new.count <= MetricsReportCheck.largestNewNameCountPerDay else { return false }

        for (key, details) in new {
            try database.execute(
                sql: "INSERT INTO metricsName (serverKey, kind, name, firstSeenAt, device, type) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [serverKey, key.kind, key.name, now, details.device, details.type]
            )
            ids[key] = database.lastInsertedRowID
        }
        return true
    }

    /// Keeps each filesystem's device and type as last reported, in case it was mounted from another.
    func recordFilesystems(of sample: MetricsSample, in database: Database) throws {
        for filesystem in sample.filesystems {
            guard let id = id(MetricsTables.filesystemKind, filesystem.mountPoint) else { continue }
            try database.cachedStatement(sql: """
            UPDATE metricsName SET device = ?, type = ? WHERE id = ? AND (device IS NOT ? OR type IS NOT ?)
            """).execute(arguments: [filesystem.device, filesystem.type, id, filesystem.device, filesystem.type])
        }
    }

    func id(_ kind: String, _ name: String) -> Int64? {
        ids[Key(kind: kind, name: name)]
    }
}
