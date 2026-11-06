import Foundation
import HiveKit
import Hummingbird

enum ServerRoutes {
    static let serverPath = RouterPath("\(HiveEndpoint.servers)/:id")

    static func add(to router: Router<HiveRequestContext>, workflow: ServerWorkflow) {
        router.get(RouterPath(HiveEndpoint.servers)) { _, _ in
            try JSONResponse(workflow.store.all())
        }

        router.post(RouterPath(HiveEndpoint.servers)) { request, context in
            let draft = try await JSONRequest.decode(ServerDraft.self, from: request)
            return try await ConfigurationChangeError.answering {
                try JSONResponse(workflow.add(draft, by: context.requireDevice()), status: .created)
            }
        }

        router.get(serverPath) { _, context in
            guard let id = context.idParameter, let server = try workflow.store.server(id: id) else {
                return JSONResponse(status: .notFound)
            }
            return try JSONResponse(server)
        }

        router.put(serverPath) { request, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            let draft = try await JSONRequest.decode(ServerDraft.self, from: request)
            return try await ConfigurationChangeError.answering {
                guard let server = try workflow.change(id: id, to: draft, by: context.requireDevice()) else {
                    return JSONResponse(status: .notFound)
                }
                return try JSONResponse(server)
            }
        }

        router.delete(serverPath) { _, context in
            guard let id = context.idParameter else { return JSONResponse(status: .notFound) }
            return JSONResponse(status: try workflow.remove(id: id, by: context.requireDevice()) ? .noContent : .notFound)
        }
    }
}
