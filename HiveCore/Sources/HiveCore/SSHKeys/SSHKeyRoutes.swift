import Foundation
import HiveKit
import Hummingbird

enum SSHKeyRoutes {
    static let path = RouterPath("\(HiveEndpoint.servers)/:id/ssh-key")

    static func add(to router: Router<HiveRequestContext>, workflow: ServerSSHKeyWorkflow) {
        router.get(path) { _, context in
            guard let id = context.idParameter, let key = try workflow.key(forServer: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(key)
        }

        router.post(path) { _, context in
            guard let id = context.idParameter,
                  let key = try workflow.makeNewKey(forServer: id, by: context.requireDevice())
            else { return JSONResponse(status: .notFound) }
            return try JSONResponse(key, status: .created)
        }
    }
}
