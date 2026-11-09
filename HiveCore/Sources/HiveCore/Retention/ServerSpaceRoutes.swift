import Foundation
import HiveKit
import Hummingbird

enum ServerSpaceRoutes {
    static func add(to router: Router<HiveRequestContext>, reader: ServerSpaceReader) {
        router.get(RouterPath("\(HiveEndpoint.servers)/:id/space")) { _, context in
            guard let id = context.idParameter, let space = try reader.space(ofServer: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(space)
        }
    }
}
