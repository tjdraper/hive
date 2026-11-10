import Foundation
import HiveKit
import Hummingbird
import os

/// Deleting snapshots by hand: one, or all of a job's or a server's, removed ones included. Each is
/// confirmed, and answered 202 once recorded, since the queue deletes them when it's free.
enum SnapshotDeletionRoutes {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Retention")

    static func add(
        to router: Router<HiveRequestContext>,
        store: SnapshotDeletionStore,
        runs: BackupRunCoordinator,
        confirmations: ConfirmationVerifier
    ) {
        typealias Handler = @Sendable (Request, HiveRequestContext, (UUID) -> SnapshotDeletionScope) async throws -> JSONResponse
        let request: Handler = { request, context, scope in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            let deviceID = try context.requireDevice()
            switch try store.request(scope(id), isConfirmed: confirmed.isConfirmed, by: deviceID, at: confirmations.now()) {
            case .requested(let count):
                logger.notice("A device asked to delete \(count, privacy: .public) snapshots")
                await runs.requestDeletions()
                return JSONResponse(status: .accepted)
            case .nothingToDelete:
                return JSONResponse(status: .notFound)
            case .beingWritten:
                return JSONResponse(status: .conflict)
            }
        }

        router.delete(RouterPath("\(HiveEndpoint.snapshots)/:id")) { try await request($0, $1, SnapshotDeletionScope.snapshot) }
        router.delete(RouterPath("\(HiveEndpoint.jobs)/:id/snapshots")) { try await request($0, $1, SnapshotDeletionScope.job) }
        router.delete(RouterPath("\(HiveEndpoint.servers)/:id/snapshots")) { try await request($0, $1, SnapshotDeletionScope.server) }
    }
}
