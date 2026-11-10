import Foundation
import HiveKit
import Hummingbird

enum EmailRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: EmailSettingsWorkflow, confirmations: ConfirmationVerifier) {
        router.get(RouterPath(HiveEndpoint.email)) { _, _ in
            try JSONResponse(workflow.state())
        }

        router.put(RouterPath(HiveEndpoint.email)) { request, context in
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            let change = try confirmed.decode(EmailSettingsChange.self)
            return try await ConfigurationChangeError.answering {
                try JSONResponse(workflow.change(change, isConfirmed: confirmed.isConfirmed, by: context.requireDevice()))
            }
        }

        router.delete(RouterPath(HiveEndpoint.email)) { _, context in
            JSONResponse(status: try workflow.turnOff(by: context.requireDevice()) ? .noContent : .notFound)
        }

        router.post(RouterPath(HiveEndpoint.testEmail)) { _, _ in
            try JSONResponse(await workflow.sendTest())
        }
    }
}
