import Foundation
import GRDB
import HiveKit
import Hummingbird
import os

/// Each server's `MetricAlertLimits`, kept with the server so recovery files hold them. A server on the
/// defaults keeps none, so it follows them if they change.
struct MetricAlertLimitsStore: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Alerts")

    let database: HiveDatabase
    let now: @Sendable () -> Date

    /// Nil when there's no such server.
    func limits(forServer serverID: UUID) throws -> MetricAlertLimits? {
        try database.writer.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT metricAlertLimits FROM server WHERE id = ?", arguments: [serverID])
            else { return nil }
            return try Self.limits(stored: row["metricAlertLimits"])
        }
    }

    /// Saved with its audit entry, unless nothing changed. Returns nil when there's no such server.
    func change(forServer serverID: UUID, to limits: MetricAlertLimits, by deviceID: UUID) throws -> MetricAlertLimits? {
        let date = now()
        let changed: Bool? = try database.writer.write { database in
            let sql = "SELECT name, metricAlertLimits FROM server WHERE id = ?"
            guard let row = try Row.fetchOne(database, sql: sql, arguments: [serverID]) else { return nil }
            let old = try Self.limits(stored: row["metricAlertLimits"])
            guard old != limits else { return false }
            let stored = limits == .defaults ? nil : String(bytes: try JSONEncoder().encode(limits), encoding: .utf8)
            try database.execute(sql: "UPDATE server SET metricAlertLimits = ? WHERE id = ?", arguments: [stored, serverID])
            let event = AuditEvent.server(serverID: serverID, serverName: row["name"], change: .metricAlertLimits(old: old, new: limits))
            try AuditLog.record(event, by: deviceID, at: date, in: database)
            return true
        }
        guard let changed else { return nil }
        if changed { Self.logger.notice("Changed a server's metric alert limits") }
        return limits
    }

    private static func limits(stored: String?) throws -> MetricAlertLimits {
        try stored.map { try JSONDecoder().decode(MetricAlertLimits.self, from: Data($0.utf8)) } ?? .defaults
    }
}

enum MetricAlertLimitsRoutes {
    static let path = RouterPath("\(HiveEndpoint.servers)/:id/metrics/alert-limits")

    static func add(to router: Router<HiveRequestContext>, store: MetricAlertLimitsStore) {
        router.get(path) { _, context in
            guard let id = context.idParameter, let limits = try store.limits(forServer: id) else { return JSONResponse(status: .notFound) }
            return try JSONResponse(limits)
        }

        router.put(path) { request, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let limits = try await JSONRequest.decode(MetricAlertLimits.self, from: request)
            guard limits.isValid else { return JSONResponse(status: .badRequest) }
            guard let saved = try store.change(forServer: id, to: limits, by: context.requireDevice()) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(saved)
        }
    }
}

/// The store's migration for metric alerts, registered in order with the rest in `HiveDatabaseMigrator`.
extension HiveDatabaseMigrator {
    static func addMetricAlerts(_ database: Database) throws {
        try database.alter(table: "server") { table in
            // `MetricAlertLimits` as JSON, or empty for the defaults.
            table.add(column: "metricAlertLimits", .text)
        }
        try database.alter(table: "scout") { table in
            // When the server last started, on its clock, as its newest sample said, so a restart is
            // emailed about once.
            table.add(column: "bootedAt", .integer)
        }
    }
}
