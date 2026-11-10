import HiveKit

extension BackupFailure {
    /// Why a run, a directory or a database failed, in a sentence.
    var message: String {
        switch self {
        case .driveNotChosen: "No backup drive is chosen."
        case .driveMissing: "The backup drive wasn't connected."
        case .driveNotThisHives: "The backup drive isn't marked as this Hive's."
        case .noSSHKey: "The server has no key of Hive's yet."
        case .noConfirmedHostKey: "The server's host key hasn't been confirmed."
        case .hostKeyChanged: "The server showed a host key other than the confirmed one, so Hive didn't connect."
        case .loginRefused: "The server turned down Hive's key."
        case .unreachable: "Couldn't reach the server."
        case .stalled: "The server stopped answering partway through."
        case .sourceMissing: "A directory isn't on the server, or isn't a directory."
        case .sourceEmpty: "A directory on the server is empty."
        case .sourceUnreadable: "Hive can't read a directory on the server."
        case .someFilesNotTransferred: "Some files or their details couldn't be copied."
        case .databasePasswordMissing: "No password is saved for the database."
        case .dockerUnavailable: "Hive couldn't list the server's Docker containers."
        case .databaseContainerNotFound: "No running container has the database's service name."
        case .databaseContainerNotUnique: "More than one running container has the database's service name."
        case .databaseDumpToolMissing: "The dump tool isn't installed where the database runs."
        case .databaseUnreachable: "The dump couldn't reach the database."
        case .databaseLoginRefused: "The database turned down the user and password."
        case .databaseMissing: "There's no database with that name."
        case .databaseNotPermitted: "The database user lacks a privilege the dump needs."
        case .databaseDumpEmpty: "The dump came back empty."
        case .databaseDumpIncomplete: "The dump ended before it was complete."
        case .databaseDumpFailed: "The dump failed."
        case .couldNotWriteSnapshot: "Hive couldn't write to the backup drive."
        case .cancelled: "Cancelled."
        case .interrupted: "Hive stopped while it ran. The next run carries on from where it got to."
        case .failed: "It failed for a reason Hive couldn't tell."
        }
    }
}
