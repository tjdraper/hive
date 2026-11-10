import Foundation
import HiveKit

/// Snapshots the person asked to delete: one, or all of a job's or a server's, removed ones included.
/// Hive deletes them between runs, after Touch ID or the password.
struct SnapshotDeletionRequest: Identifiable {
    enum Scope {
        case snapshot(SnapshotSummary)
        case job(id: UUID, count: Int)
        /// Its removed jobs' too.
        case server(id: UUID)
    }

    let id = UUID()
    let scope: Scope
    /// The job's, or for a whole server, the server's.
    let name: String

    var path: String {
        switch scope {
        case .snapshot(let snapshot): HiveEndpoint.snapshot(snapshot.id)
        case .job(let id, _): HiveEndpoint.snapshots(ofJob: id)
        case .server(let id): HiveEndpoint.snapshots(ofServer: id)
        }
    }

    var title: String {
        switch scope {
        case .snapshot(let snapshot): "Delete the snapshot from \(snapshot.date.formatted(date: .abbreviated, time: .shortened))?"
        case .job(_, let count): count == 1 ? "Delete the snapshot of “\(name)”?" : "Delete all \(count) snapshots of “\(name)”?"
        case .server: "Delete all of “\(name)”'s snapshots?"
        }
    }

    var message: String {
        let when = "Hive deletes them from the backup drive once no backup is running. This can't be undone."
        return switch scope {
        case .snapshot: "Hive deletes it from the backup drive once no backup is running. This can't be undone."
        case .job: when
        case .server: "This includes the snapshots of jobs removed from it. \(when)"
        }
    }

    var buttonTitle: String {
        switch scope {
        case .snapshot, .job(_, 1): "Delete Snapshot"
        case .job, .server: "Delete All Snapshots"
        }
    }

    /// What Touch ID or the password prompt says, after "Beekeeper is trying to".
    var reason: String {
        switch scope {
        case .snapshot(let snapshot):
            "delete the snapshot of “\(name)” from \(snapshot.date.formatted(date: .abbreviated, time: .shortened))"
        case .job(_, let count): "delete \(SnapshotCount(count)) of “\(name)”"
        case .server: "delete all of “\(name)”'s snapshots"
        }
    }
}
