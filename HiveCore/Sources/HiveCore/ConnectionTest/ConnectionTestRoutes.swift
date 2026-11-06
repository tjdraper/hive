import Foundation
import HiveKit
import Hummingbird

enum ConnectionTestRoutes {
    static let path = RouterPath("\(HiveEndpoint.servers)/:id/connection-test")

    static func add(to router: Router<HiveRequestContext>, workflow: ConnectionTestWorkflow) {
        router.post(path) { _, context in
            guard let id = context.idParameter, let result = try await workflow.test(serverID: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(result)
        }
    }
}
