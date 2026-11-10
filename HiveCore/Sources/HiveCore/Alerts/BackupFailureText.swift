import HiveKit

extension BackupFailure {
    /// Why a run failed, in a sentence for an email.
    var emailReason: String {
        switch self {
        case .driveNotChosen: "No backup drive has been chosen."
        case .driveMissing: "The backup drive isn't connected."
        case .driveNotThisHives: "The connected backup drive isn't marked as this Hive's."
        case .noSSHKey: "Hive has no SSH key for the server yet."
        case .noConfirmedHostKey: "The server's host key hasn't been confirmed in Beekeeper."
        case .hostKeyChanged: "The server answered with a host key other than the confirmed one, so Hive didn't connect."
        case .loginRefused: "The server turned down Hive's SSH key. Check that its public key is in the server's authorized_keys."
        case .unreachable: "Hive couldn't reach the server."
        case .stalled: "The connection to the server stopped answering part way through."
        case .sourceMissing: "A directory to back up doesn't exist on the server, or isn't a directory."
        case .sourceEmpty: "A directory to back up is empty on the server."
        case .sourceUnreadable: "Hive's SSH user can't read a directory on the server."
        case .someFilesNotTransferred: "Some files or their attributes couldn't be copied."
        case .databasePasswordMissing: "No password is stored for a database. Enter it again in Beekeeper."
        case .dockerUnavailable: "Hive couldn't list the server's Docker containers."
        case .databaseContainerNotFound: "No running container has the database's service name."
        case .databaseContainerNotUnique: "More than one running container has the database's service name."
        case .databaseDumpToolMissing: "The database's dump tool isn't installed where the database runs."
        case .databaseUnreachable: "The dump couldn't reach the database server."
        case .databaseLoginRefused: "The database server turned down the user and password."
        case .databaseMissing: "The database doesn't exist."
        case .databaseNotPermitted: "The database user lacks a privilege the dump needs."
        case .databaseDumpEmpty: "The dump finished without writing anything."
        case .databaseDumpIncomplete: "The dump ended before it was complete."
        case .databaseDumpFailed: "The database dump failed."
        case .couldNotWriteSnapshot: "Hive couldn't write the snapshot to the backup drive."
        case .cancelled: "The run was cancelled."
        case .interrupted: "Hive stopped while the run was going."
        case .failed: "Something unexpected went wrong. The system log may say more."
        }
    }
}
