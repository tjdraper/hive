import Foundation
import HiveKit

/// A job as the editor holds it while it's changed. Each row keeps an identity of its own so the lists
/// can grow and shrink under the person's hands, and each database remembers whether Hive has its
/// password, which the job only ever says yes or no to.
struct JobEditorDraft: Equatable {
    struct Directory: Identifiable, Equatable {
        let id = UUID()
        var path = ""
        var folder = ""
    }

    struct Database: Identifiable, Equatable {
        let id = UUID()
        /// Nil until Hive has it. A database it already has keeps its ID, and with it its password.
        var savedID: UUID?
        var kind = DatabaseKind.mysql
        var isInContainer = true
        var serviceName = ""
        var user = ""
        var name = ""
        var hasSavedPassword = false
        /// Nil keeps the password Hive has, or leaves none.
        var newPassword: String?
    }

    struct Time: Identifiable, Equatable {
        let id = UUID()
        var time: TimeOfDay
    }

    var name = ""
    var directories: [Directory] = []
    var databases: [Database] = []
    var times = [Time(time: TimeOfDay(hour: 0, minute: 0))]
    var retention = RetentionTiers.suggested

    /// A new job: run at midnight and keep what C6 suggests.
    init() {}

    init(_ job: BackupJob) {
        name = job.name
        directories = job.directories.map { Directory(path: $0.path, folder: $0.folder) }
        databases = job.databases.map { database in
            let settings = database.settings
            var row = Database(
                savedID: database.id,
                kind: settings.kind,
                user: settings.user,
                name: settings.name,
                hasSavedPassword: database.hasPassword
            )
            switch settings.location {
            case .host:
                row.isInContainer = false
            case .container(let serviceName):
                row.serviceName = serviceName
            }
            return row
        }
        times = job.times.map { Time(time: $0) }
        retention = job.retention
    }

    /// What's sent to Hive. Its places in each list are the ones Hive's problems refer to.
    var draft: BackupJobDraft {
        BackupJobDraft(
            name: name,
            directories: directories.map { BackupDirectory(path: $0.path, folder: $0.folder) },
            databases: databases.map(\.draft),
            times: times.map(\.time),
            retention: retention
        )
    }

    var rowIDs: [UUID] {
        directories.map(\.id) + databases.map(\.id) + times.map(\.id)
    }

    /// Hive checks everything else, and says which field it turned down.
    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension JobEditorDraft.Database {
    var draft: BackupDatabaseDraft {
        let location: DatabaseLocation = isInContainer ? .container(serviceName: serviceName) : .host
        return BackupDatabaseDraft(
            id: savedID,
            settings: DatabaseSettings(kind: kind, location: location, user: user, name: name),
            password: newPassword
        )
    }
}

extension JobEditorDraft.Directory {
    /// The folder a path's backup goes in unless the person names another: the path's last part.
    static func suggestedFolder(for path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }
}
