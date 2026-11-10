import Foundation

/// A job's snapshots on the chosen backup drive.
public struct JobSnapshots: Codable, Hashable, Sendable {
    /// Newest first.
    public let snapshots: [SnapshotSummary]
    /// The job's folder on the Hive Mac, for Show in Finder there. Nil while the drive isn't mounted,
    /// or before the job's first snapshot.
    public let folderPath: String?
    /// What the job's snapshots take on the drive, each file once. Nil until they're counted, which
    /// happens after its next run or retention pass.
    public let usedBytes: Int64?

    public init(snapshots: [SnapshotSummary], folderPath: String?, usedBytes: Int64?) {
        self.snapshots = snapshots
        self.folderPath = folderPath
        self.usedBytes = usedBytes
    }
}

public struct SnapshotSummary: Codable, Hashable, Identifiable, Sendable {
    public enum State: String, Codable, Hashable, Sendable {
        case complete
        /// Being written, or left by a run that failed, for the next run to pick up.
        case partial
        /// Retention is removing it.
        case removing
    }

    public let id: UUID
    /// When it completed, or for one that hasn't, when it started.
    public let date: Date
    public let state: State
    /// Its folder, within the job's.
    public let folder: String
    /// What removing it would free. Nil until it's counted, and for a moment after a change nearby.
    public let freesBytes: Int64?

    public init(id: UUID, date: Date, state: State, folder: String, freesBytes: Int64?) {
        self.id = id
        self.date = date
        self.state = state
        self.folder = folder
        self.freesBytes = freesBytes
    }
}
