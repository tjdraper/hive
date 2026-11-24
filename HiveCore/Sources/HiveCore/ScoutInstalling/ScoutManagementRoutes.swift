import Foundation
import HiveKit
import Hummingbird

/// A device's routes for acting on a server's Scout over SSH.
enum ScoutManagementRoutes {
    static let checkPath = RouterPath("\(HiveEndpoint.servers)/:id/scout-check")
    static let actionPath = RouterPath("\(HiveEndpoint.servers)/:id/scout-action")

    static func add(to router: Router<HiveRequestContext>, workflow: ScoutManagementWorkflow, confirmations: ConfirmationVerifier) {
        router.post(checkPath) { _, context in
            guard let id = context.idParameter, let result = try await workflow.check(serverID: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(result)
        }

        router.post(actionPath) { request, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            let action = try confirmed.decode(ScoutActionRequest.self).action
            do {
                let deviceID = try context.requireDevice()
                guard let result = try await workflow.perform(action, onServer: id, isConfirmed: confirmed.isConfirmed, by: deviceID) else {
                    return JSONResponse(status: .notFound)
                }
                return try JSONResponse(result)
            } catch EnrollmentWindowError.restarting {
                return JSONResponse(status: .serviceUnavailable)
            }
        }
    }
}
