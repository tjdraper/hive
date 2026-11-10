import Foundation
import HiveKit
import Hummingbird

enum SnapshotRoutes {
    static func add(to router: Router<HiveRequestContext>, reader: JobSnapshotReader, removedJobs: RemovedJobReader) {
        router.get(RouterPath("\(HiveEndpoint.jobs)/:id/snapshots")) { _, context in
            guard let id = context.idParameter, let snapshots = try reader.snapshots(ofJob: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(snapshots)
        }

        router.get(RouterPath(HiveEndpoint.removedJobs)) { _, _ in
            try JSONResponse(removedJobs.removedJobs())
        }
    }
}
