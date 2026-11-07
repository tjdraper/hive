import Foundation
import HiveKit
import Hummingbird

enum BackupRunRoutes {
    static let path = RouterPath("\(HiveEndpoint.jobs)/:id/run")

    static func add(to router: Router<HiveRequestContext>, coordinator: BackupRunCoordinator, statuses: JobStatusReader) {
        router.post(path) { _, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            switch try await coordinator.runNow(jobID: id, by: context.requireDevice()) {
            case .queued:
                guard let status = try await statuses.statuses(ofJob: id).first else { return JSONResponse(status: .notFound) }
                return try JSONResponse(status, status: .accepted)
            case .alreadyQueued:
                return JSONResponse(status: .conflict)
            case .unknownJob:
                return JSONResponse(status: .notFound)
            }
        }

        router.delete(path) { _, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let cancelled = try await coordinator.cancel(jobID: id, by: context.requireDevice())
            return JSONResponse(status: cancelled ? .noContent : .notFound)
        }

        router.get(path) { _, context in
            guard let id = context.idParameter, let status = try await statuses.statuses(ofJob: id).first else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(status)
        }

        router.get(RouterPath(HiveEndpoint.jobStatus)) { _, _ in
            try JSONResponse(await statuses.statuses())
        }
    }
}
