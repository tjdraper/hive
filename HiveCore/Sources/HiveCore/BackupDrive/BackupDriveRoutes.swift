import Foundation
import HiveKit
import Hummingbird

enum BackupDriveRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: BackupDriveWorkflow) {
        router.get(RouterPath(HiveEndpoint.backupDrive)) { _, _ in
            try JSONResponse(workflow.state())
        }

        router.put(RouterPath(HiveEndpoint.backupDrive)) { request, context in
            let choice = try await JSONRequest.decode(BackupDriveChoice.self, from: request)
            do {
                return try JSONResponse(workflow.choose(choice, by: context.requireDevice()))
            } catch BackupDriveChoiceError.refused(let problem) {
                return try JSONResponse(BackupDriveRefusal(problem: problem), status: .unprocessableContent)
            }
        }
    }
}
