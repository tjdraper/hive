import Foundation
import GRDB
import HiveKit
import os
import ScoutProtocol

/// Names the containers a server's Scout reports only by ID (§4), with a read-only `docker ps` over
/// SSH. It asks only when a sample holds a container Hive hasn't named, at most once a minute for each
/// server, and once `docker ps` has failed, only a day later or after the server's SSH details change.
struct ContainerNamingWorkflow: Sendable {
    enum Outcome: Equatable {
        case nothingNew
        /// Not yet due, or the server has no SSH details Hive can use.
        case notAsked
        case named(listed: Int)
        case failed
    }

    static let askInterval: TimeInterval = 60
    static let retryAfterFailure: TimeInterval = 86_400

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Metrics")

    let database: MetricsDatabase
    let targets: SSHTargetLoader
    let ssh: any SSHRunning
    let now: @Sendable () -> Date

    /// The SSH details `docker ps` ran with, so a failure is retried once they change.
    static func connectionKey(_ target: SSHTarget) -> String {
        "\(target.connection.user)@\(target.connection.host):\(target.connection.port)"
    }

    func nameContainers(of sample: MetricsSample, forServer serverID: UUID) async -> Outcome {
        let ids = Set(sample.containers?.top.map(\.name) ?? [])
        guard !ids.isEmpty else { return .nothingNew }
        do {
            let serverKey: Int64
            switch try claim(ids, forServer: serverID) {
            case .allNamed: return .nothingNew
            case .notDue: return .notAsked
            case .due(let key): serverKey = key
            }
            guard case .ready(let target) = try targets.target(forServer: serverID) else { return .notAsked }
            let connection = Self.connectionKey(target)
            if try failedRecently(serverKey: serverKey, connection: connection) { return .notAsked }

            let answer = try await ssh.run(ContainerListing.command, on: target)
            guard answer.status == 0 else {
                let reason = SSHFailureReader.failure(in: answer)?.rawValue ?? "failed"
                Self.logger.notice("Couldn't list a server's containers (\(reason, privacy: .public)); asking again in a day")
                try recordFailure(serverKey: serverKey, connection: connection)
                return .failed
            }
            let names = ContainerListing.names(in: answer.standardOutput)
            try keep(names, reported: ids, serverKey: serverKey)
            Self.logger.info("Named a server's containers: \(names.count, privacy: .public) listed")
            return .named(listed: names.count)
        } catch {
            Self.logger.error("Couldn't name a server's containers: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    private enum Claim {
        case allNamed
        case notDue
        /// The server's key, with the time it was asked recorded, so two reports can't both ask.
        case due(Int64)
    }

    private func claim(_ ids: Set<String>, forServer serverID: UUID) throws -> Claim {
        let now = now()
        return try database.writer.write { database -> Claim in
            let key = try Int64.fetchOne(database, sql: "SELECT id FROM metricsServer WHERE serverID = ?", arguments: [serverID])
            guard let serverKey = key else { return .allNamed }
            let known = try Set(String.fetchAll(
                database,
                sql: "SELECT containerID FROM containerName WHERE serverKey = ? AND containerID IN (SELECT value FROM json_each(?))",
                arguments: [serverKey, String(data: JSONEncoder().encode(Array(ids)), encoding: .utf8)]
            ))
            guard !ids.isSubset(of: known) else { return .allNamed }
            // An asking time ahead of now is from a clock set back, so it's due rather than waited out.
            try database.execute(sql: """
            UPDATE metricsServer SET containersAskedAt = ?
            WHERE id = ? AND (containersAskedAt IS NULL OR containersAskedAt <= ? OR containersAskedAt > ?)
            """, arguments: [now, serverKey, now.addingTimeInterval(-Self.askInterval), now])
            return database.changesCount == 1 ? .due(serverKey) : .notDue
        }
    }

    private func failedRecently(serverKey: Int64, connection: String) throws -> Bool {
        let row = try database.writer.read {
            let sql = "SELECT dockerFailedAt, dockerFailedConnection FROM metricsServer WHERE id = ?"
            return try Row.fetchOne($0, sql: sql, arguments: [serverKey])
        }
        guard let failedAt: Date = row?["dockerFailedAt"], row?["dockerFailedConnection"] == connection else { return false }
        let since = now().timeIntervalSince(failedAt)
        return since >= 0 && since < Self.retryAfterFailure
    }

    private func recordFailure(serverKey: Int64, connection: String) throws {
        try database.writer.write {
            try $0.execute(
                sql: "UPDATE metricsServer SET dockerFailedAt = ?, dockerFailedConnection = ? WHERE id = ?",
                arguments: [now(), connection, serverKey]
            )
        }
    }

    /// Keeps every container listed, and the reported ones `docker ps` didn't list without a name, since
    /// an ID is never reused: one it doesn't list now, such as Podman's, it never will, and asking again
    /// every minute would only repeat that.
    private func keep(_ names: [ContainerName], reported ids: Set<String>, serverKey: Int64) throws {
        let now = now()
        try database.writer.write { database in
            try database.execute(
                sql: "UPDATE metricsServer SET dockerFailedAt = NULL, dockerFailedConnection = NULL WHERE id = ?",
                arguments: [serverKey]
            )
            let statement = try database.cachedStatement(sql: """
            INSERT INTO containerName (serverKey, containerID, name, swarmService, composeProject, composeService, seenAt)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(serverKey, containerID) DO UPDATE SET name = excluded.name, swarmService = excluded.swarmService,
                composeProject = excluded.composeProject, composeService = excluded.composeService, seenAt = excluded.seenAt
            """)
            for container in names {
                try statement.execute(arguments: [
                    serverKey, container.containerID, container.name, container.swarmService,
                    container.composeProject, container.composeService, now,
                ])
            }
            let listed = Set(names.map(\.containerID))
            for id in ids.subtracting(listed) {
                try database.execute(sql: """
                INSERT INTO containerName (serverKey, containerID, seenAt) VALUES (?, ?, ?) ON CONFLICT DO NOTHING
                """, arguments: [serverKey, id, now])
            }
        }
    }
}
