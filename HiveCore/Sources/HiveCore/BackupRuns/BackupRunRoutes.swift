import Foundation
import HiveKit
import Hummingbird

enum BackupRunRoutes {
    static let path = RouterPath("\(HiveEndpoint.jobs)/:id/run")

    static func add(to router: Router<HiveRequestContext>, coordinator: BackupRunCoordinator) {
        router.post(path) { _, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            switch try await coordinator.start(jobID: id, by: context.requireDevice()) {
            case .started(let run):
                return try JSONResponse(run, status: .accepted)
            case .busy:
                return JSONResponse(status: .conflict)
            case .unknownJob:
                return JSONResponse(status: .notFound)
            }
        }

        router.get(path) { _, context in
            guard let id = context.idParameter, let run = await coordinator.latestRun(ofJob: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(run)
        }
    }
}
