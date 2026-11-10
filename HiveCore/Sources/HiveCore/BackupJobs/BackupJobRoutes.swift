import Foundation
import HiveKit
import Hummingbird

enum BackupJobRoutes {
    static let jobPath = RouterPath("\(HiveEndpoint.jobs)/:id")
    static let serverJobsPath = RouterPath("\(HiveEndpoint.servers)/:id\(HiveEndpoint.jobs)")

    static func add(to router: Router<HiveRequestContext>, workflow: BackupJobWorkflow, confirmations: ConfirmationVerifier) {
        router.get(RouterPath(HiveEndpoint.jobs)) { _, _ in
            try JSONResponse(workflow.store.all())
        }

        router.get(serverJobsPath) { _, context in
            guard let serverID = context.idParameter, let jobs = try workflow.store.jobs(onServer: serverID) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(jobs)
        }

        router.post(serverJobsPath) { request, context in
            guard let serverID = context.idParameter else { return JSONResponse(status: .notFound) }
            let draft = try await JSONRequest.decode(BackupJobDraft.self, from: request)
            return try await ConfigurationChangeError.answering {
                guard let job = try workflow.add(draft, toServer: serverID, by: context.requireDevice()) else {
                    return JSONResponse(status: .notFound)
                }
                return try JSONResponse(job, status: .created)
            }
        }

        router.get(jobPath) { _, context in
            guard let id = context.idParameter, let job = try workflow.store.job(id: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(job)
        }

        router.put(jobPath) { request, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            let draft = try confirmed.decode(BackupJobDraft.self)
            return try await ConfigurationChangeError.answering {
                let deviceID = try context.requireDevice()
                guard let job = try workflow.change(id: id, to: draft, isConfirmed: confirmed.isConfirmed, by: deviceID) else {
                    return JSONResponse(status: .notFound)
                }
                return try JSONResponse(job)
            }
        }

        router.delete(jobPath) { _, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            return JSONResponse(status: try workflow.remove(id: id, by: context.requireDevice()) ? .noContent : .notFound)
        }
    }
}
