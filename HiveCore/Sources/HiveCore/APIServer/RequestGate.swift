import HiveKit
import Hummingbird
import os

/// Stands in front of routing and turns away every request that isn't signed in, unless it's for one of
/// the few open routes. It looks only at the method and path, so a refused request's body is never read.
struct RequestGate<Next: HTTPResponder>: HTTPResponder {
    typealias Context = Next.Context

    struct OpenRoute: Hashable {
        let method: HTTPRequest.Method
        let path: String
    }

    static var openRoutes: Set<OpenRoute> {
        [OpenRoute(method: .get, path: HiveEndpoint.health)]
    }

    private static var logger: Logger {
        Logger(subsystem: HiveLog.subsystem, category: "APIServer")
    }

    let next: Next

    // Hummingbird's responders run concurrently. Matching them lets the context pass to the next one.
    @concurrent func respond(to request: Request, context: Context) async throws -> Response {
        // The router matches on this same path string, so an open route can't reach any other handler.
        guard Self.openRoutes.contains(OpenRoute(method: request.method, path: request.uri.path)) else {
            Self.logger.debug("Refused a request that isn't signed in")
            return Response(status: .unauthorized)
        }
        return try await next.respond(to: request, context: context)
    }
}
