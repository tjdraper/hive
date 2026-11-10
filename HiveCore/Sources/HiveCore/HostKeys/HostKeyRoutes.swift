import Foundation
import HiveKit
import Hummingbird

enum HostKeyRoutes {
    static let hostKeyPath = RouterPath("\(HiveEndpoint.servers)/:id/host-key")
    static let scanPath = RouterPath("\(HiveEndpoint.servers)/:id/host-key/scan")

    static func add(to router: Router<HiveRequestContext>, workflow: HostKeyWorkflow, confirmations: ConfirmationVerifier) {
        router.post(scanPath) { _, context in
            guard let id = context.idParameter, let result = try await workflow.scan(serverID: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(result)
        }

        router.put(hostKeyPath) { request, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            let confirmation = try confirmed.decode(HostKeyConfirmation.self)
            let outcome = try workflow.confirm(
                serverID: id,
                fingerprint: confirmation.fingerprint,
                isConfirmed: confirmed.isConfirmed,
                by: context.requireDevice()
            )
            switch outcome {
            case nil:
                return JSONResponse(status: .notFound)
            case .confirmed(let server):
                return try JSONResponse(server)
            case .refused(let reason):
                return try JSONResponse(HostKeyConfirmationRefusal(reason: reason), status: .conflict)
            }
        }
    }
}
