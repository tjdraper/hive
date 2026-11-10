import Foundation
import HiveKit
import Hummingbird

enum IdentityRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: IdentityRegenerationWorkflow, confirmations: ConfirmationVerifier) {
        router.post(RouterPath(HiveEndpoint.identityRegeneration)) { request, context in
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            try workflow.regenerate(isConfirmed: confirmed.isConfirmed, by: context.requireDevice())
            return JSONResponse(status: .accepted)
        }
    }
}
