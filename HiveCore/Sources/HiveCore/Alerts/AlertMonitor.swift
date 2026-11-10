import Foundation
import HiveKit
import os

/// Works out which alerts are open (§13) from finished runs and the state of Hive, once a minute,
/// and has their emails sent.
actor AlertMonitor {
    static let checkInterval: Duration = .seconds(60)

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Alerts")

    let mailer: AlertMailer
    private let store: AlertStore
    private let finishedRuns: FinishedRunAlerts
    private let standing: StandingAlertCheck
    private let now: @Sendable () -> Date

    init(
        database: HiveDatabase,
        drives: BackupDriveLocator,
        statuses: JobStatusReader,
        scanner: any HostKeyScanning,
        fullDiskAccess: @escaping @Sendable () -> FullDiskAccess,
        delivery: EmailDelivery,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date
    ) {
        store = AlertStore(database: database)
        finishedRuns = FinishedRunAlerts(
            database: database,
            servers: ServerStore(database: database),
            scanner: scanner,
            fullDiskAccess: fullDiskAccess
        )
        standing = StandingAlertCheck(database: database, drives: drives, statuses: statuses, fullDiskAccess: fullDiskAccess)
        mailer = AlertMailer(
            store: store,
            messages: AlertMessageBuilder(database: database, drives: drives, calendar: calendar),
            delivery: delivery,
            now: now
        )
        self.now = now
    }

    /// Until the task running it is cancelled. The first check waits an interval, so jobs due while
    /// Hive was off are queued before they could be taken for overdue.
    func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.checkInterval)
            guard !Task.isCancelled else { break }
            await check()
            await mailer.sendOwed()
        }
        await mailer.stop()
    }

    /// Updates the alerts in the store, without sending anything.
    func check() async {
        do {
            try await workThroughFinishedRuns()
            let changes = try await standing.changes(open: store.all())
            log(try store.apply(changes, at: now()))
            let reminders = try store.oweReminders(at: now())
            if reminders > 0 { Self.logger.notice("Reminders owed for \(reminders, privacy: .public) alerts") }
        } catch {
            Self.logger.error("Couldn't check alerts: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Each run's alerts are saved with moving past it, so a restart works through it again or not at all.
    private func workThroughFinishedRuns() async throws {
        for run in try finishedRuns.finishedRuns(after: store.checkedThrough()) {
            let changes = try await finishedRuns.changes(for: run, open: Set(store.all().map(\.key)))
            log(try store.apply(changes, at: now(), checkedThrough: run.id))
        }
    }

    private func log(_ applied: AlertStore.Applied) {
        for facts in applied.opened {
            Self.logger.notice("Opened an alert: \(facts.kind, privacy: .public)")
        }
        for facts in applied.ended {
            Self.logger.notice("Ended an alert: \(facts.kind, privacy: .public)")
        }
    }
}
