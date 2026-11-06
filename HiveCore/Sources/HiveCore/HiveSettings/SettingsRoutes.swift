import Foundation
import HiveKit
import Hummingbird

enum SettingsRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: HiveSettingsWorkflow) {
        router.get(RouterPath(HiveEndpoint.settings)) { _, _ in
            try JSONResponse(await workflow.state())
        }

        router.put(RouterPath(HiveEndpoint.settings)) { request, context in
            let requested = try await JSONRequest.decode(HiveSettings.self, from: request)
            do {
                return try JSONResponse(await workflow.change(to: requested, by: context.requireDevice()))
            } catch SettingsChangeError.refused(let problem) {
                return try JSONResponse(SettingsRefusal(problem: problem), status: .unprocessableContent)
            }
        }
    }
}
