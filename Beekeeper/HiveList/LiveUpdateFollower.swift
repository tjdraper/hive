import Foundation
import HiveKit
import os

/// Follows one Hive's live updates, reconnecting when they stop, and hands each to what it changes.
struct LiveUpdateFollower {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "LiveUpdates")
    /// Soon, since the usual reason is a session that ran out, then less often while the Hive stays away.
    private static let firstRetry = Duration.seconds(1)
    private static let longestRetry = Duration.seconds(30)
    private static let connectionCheck = Duration.seconds(2)

    let link: HiveLink
    let statuses: JobStatusStore
    let recovery: RecoveryFileCopies
    let onAddresses: (HiveAddresses) -> Void

    /// Until cancelled. Opening live updates signs in again, so a Hive that comes back after a restart
    /// shows as connected without waiting for anything else.
    func follow() async {
        var retry = Self.firstRetry
        while !Task.isCancelled {
            guard mayConnect else {
                try? await Task.sleep(for: Self.connectionCheck)
                continue
            }
            do {
                for try await update in try await link.liveUpdates() {
                    apply(update)
                    retry = Self.firstRetry
                }
                Self.logger.info("Live updates ended")
            } catch is CancellationError {
                break
            } catch {
                Self.logger.notice("Live updates failed: \(String(describing: type(of: error)), privacy: .public)")
            }
            statuses.liveUpdatesStopped()
            try? await Task.sleep(for: retry)
            retry = min(retry * 2, Self.longestRetry)
        }
        statuses.liveUpdatesStopped()
    }

    /// Not while trying again can't help, or would count against the device as a failed sign-in.
    private var mayConnect: Bool {
        switch link.status {
        case .connecting, .connected, .offline, .failed: true
        case .pairingAgain, .restarting, .identityChanged, .notRecognized, .notPaired, .lockedOut, .needsUpdate: false
        }
    }

    private func apply(_ update: LiveUpdate) {
        switch update {
        case .recovery(let state):
            recovery.receive(state)
        case .addresses(let addresses):
            onAddresses(addresses)
        case .jobStatuses, .jobStatus, .event, .heartbeat:
            statuses.apply(update)
        }
    }
}
