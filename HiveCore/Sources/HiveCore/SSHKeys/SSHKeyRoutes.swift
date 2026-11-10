import Foundation
import HiveKit
import Hummingbird

enum SSHKeyRoutes {
    static let path = RouterPath("\(HiveEndpoint.servers)/:id/ssh-key")

    static func add(to router: Router<HiveRequestContext>, workflow: ServerSSHKeyWorkflow, confirmations: ConfirmationVerifier) {
        router.get(path) { _, context in
            guard let id = context.idParameter, let key = try workflow.key(forServer: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(key)
        }

        router.post(path) { request, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            guard let key = try workflow.makeNewKey(forServer: id, isConfirmed: confirmed.isConfirmed, by: context.requireDevice()) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(key, status: .created)
        }
    }
}
