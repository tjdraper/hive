import Foundation
import HiveKit
import Hummingbird

enum BackupDriveRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: BackupDriveWorkflow, runs: BackupRunCoordinator) {
        router.get(RouterPath(HiveEndpoint.backupDrive)) { _, _ in
            try JSONResponse(workflow.state())
        }

        router.put(RouterPath(HiveEndpoint.backupDrive)) { request, context in
            let choice = try await JSONRequest.decode(BackupDriveChoice.self, from: request)
            do {
                let chosen = try workflow.choose(choice, by: context.requireDevice())
                // Counts what was taken over, so its space shows before retention starts again. Taking
                // snapshots over paused retention, so the pass removes nothing.
                if chosen.tookOverSnapshots { await runs.requestRetentionPass() }
                return try JSONResponse(chosen.state)
            } catch BackupDriveChoiceError.refused(let problem) {
                return try JSONResponse(BackupDriveRefusal(problem: problem), status: .unprocessableContent)
            }
        }
    }
}
