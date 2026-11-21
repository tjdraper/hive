import Foundation
import GRDB
import ScoutProtocol

/// What Hive knows of a server's reporting, apart from its figures. Kept in the metrics database, so a
/// sample every 10 seconds never writes to Hive's store.
struct MetricsServerRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "metricsServer"

    var id: Int64?
    let serverID: UUID
    /// Hive's clock, when the server last sent anything, kept or not.
    var lastReportAt: Date?
    /// The server's clock less Hive's, in seconds, as of the last request.
    var clockOffsetSeconds: Int64?
    /// The newest sample kept, on the server's clock, and what it said about the server.
    var lastSampleAt: Int64?
    var uptimeSeconds: Double?
    var scoutVersion: String?
    var distribution: String?
    var kernel: String?
    var processesHidden: Bool?
    /// Why the last request was refused, cleared once something is kept again.
    var lastRefusal: String?
    var lastRefusedAt: Date?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// The server's row, made the first time it reports.
    static func find(_ serverID: UUID, in database: Database) throws -> MetricsServerRecord {
        if let record = try filter(Column("serverID") == serverID).fetchOne(database) { return record }
        var record = MetricsServerRecord(serverID: serverID)
        try record.insert(database)
        return record
    }

    init(serverID: UUID) {
        self.serverID = serverID
    }

    mutating func recordFacts(of sample: MetricsSample) {
        guard sample.takenAt > lastSampleAt ?? .min else { return }
        lastSampleAt = sample.takenAt
        uptimeSeconds = sample.server.uptimeSeconds
        scoutVersion = sample.server.scoutVersion
        distribution = sample.server.distribution
        kernel = sample.server.kernel
        processesHidden = sample.server.processesHidden
    }
}
