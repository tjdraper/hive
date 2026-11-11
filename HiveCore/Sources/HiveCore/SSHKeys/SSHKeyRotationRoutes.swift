import Foundation
import HiveKit
import Hummingbird

enum SSHKeyRotationRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: SSHKeyRotationWorkflow, confirmations: ConfirmationVerifier) {
        router.get(RouterPath(HiveEndpoint.sshKeyRotation)) { _, _ in
            try await JSONResponse(workflow.state())
        }

        router.post(RouterPath(HiveEndpoint.sshKeyRotation)) { request, context in
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            do {
                let state = try await workflow.start(isConfirmed: confirmed.isConfirmed, by: context.requireDevice())
                return try JSONResponse(state, status: .accepted)
            } catch SSHKeyRotationError.alreadyRunning {
                return JSONResponse(status: .conflict)
            }
        }
    }
}
