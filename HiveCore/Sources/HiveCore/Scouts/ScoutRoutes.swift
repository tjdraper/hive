import Foundation
import HiveKit
import Hummingbird
import ScoutProtocol

/// A device's routes for a server's Scout, and the routes a Scout's own session reaches. Enrolling and
/// signing in go through the pairing and sign-in routes, in `PairingRoutes` and `SignInRoutes`.
enum ScoutRoutes {
    static let enrollmentWindowPath = RouterPath("\(HiveEndpoint.servers)/:id/enrollment-window")
    static let scoutPath = RouterPath("\(HiveEndpoint.servers)/:id/scout")

    static func add(
        to router: Router<HiveRequestContext>,
        windows: EnrollmentWindowWorkflow,
        removal: ScoutRemovalWorkflow,
        confirmations: ConfirmationVerifier
    ) {
        router.post(enrollmentWindowPath) { request, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            do {
                guard let window = try windows.open(forServer: id, isConfirmed: confirmed.isConfirmed, by: context.requireDevice()) else {
                    return JSONResponse(status: .notFound)
                }
                return try JSONResponse(window, status: .created)
            } catch EnrollmentWindowError.refused(let problem) {
                return try JSONResponse(EnrollmentWindowRefusal(problem: problem), status: .unprocessableContent)
            } catch EnrollmentWindowError.restarting {
                return JSONResponse(status: .serviceUnavailable)
            }
        }

        router.delete(enrollmentWindowPath) { _, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            try windows.close(forServer: id, by: context.requireDevice())
            return JSONResponse(status: .noContent)
        }

        router.delete(scoutPath) { _, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let removed = try removal.remove(forServer: id, by: context.requireDevice())
            return JSONResponse(status: removed ? .noContent : .notFound)
        }

        // Reached only by a Scout's session, which `RequestGate` keeps to these routes.
        router.get(RouterPath(ScoutEndpoint.session)) { _, context in
            try JSONResponse(ScoutSessionCheck(serverID: context.requireScout().serverID))
        }
    }
}
