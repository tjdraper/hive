import Foundation

/// The recovery workflows, built from the API's stores like the rest.
extension HiveAPI {
    var recoveryKey: RecoveryKeyWorkflow {
        RecoveryKeyWorkflow(store: RecoveryKeyStore(database: servers.store.database), files: recoveryFiles, now: signIn.now)
    }

    var restoreState: RestoreStateReader {
        RestoreStateReader(database: servers.store.database)
    }
}
