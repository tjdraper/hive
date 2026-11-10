import Foundation
import HiveKit

extension RunStep {
    var summary: String {
        switch self {
        case .waitingForDrive: "Waiting for the backup drive"
        case .checkingDirectories: "Checking the directories on the server"
        case .pulling(let folder): "Copying “\(folder)”"
        case .dumping(let database): "Dumping “\(database)”"
        case .completing: "Finishing the snapshot"
        }
    }
}

extension BackupRun {
    /// How many of the job's directories and databases it has finished.
    var finishedParts: Int {
        directories.count + databases.count
    }

    /// New and changed files, and dumps as stored.
    var bytesWritten: Int64 {
        directories.reduce(0) { $0 + $1.bytesTransferred } + databases.reduce(0) { $0 + $1.bytesStored }
    }

    var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }

    var vanishedFiles: Bool {
        directories.contains(where: \.vanishedFiles)
    }
}

extension Date {
    /// Such as "Today at 7:15 PM", "Tomorrow at 3:00 AM" or "Nov 7, 2026 at 3:00 AM".
    var spoken: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: self)
    }
}

extension TimeInterval {
    /// Such as "4 sec" or "1 hr, 5 min".
    var spoken: String {
        guard self >= 1 else { return "under 1 sec" }
        return Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }
}
