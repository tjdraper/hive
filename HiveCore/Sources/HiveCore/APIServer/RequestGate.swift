import Foundation
import HiveKit
import Hummingbird
import os
import ScoutProtocol

/// Stands in front of routing and turns away every request that isn't signed in, unless it's for one of
/// the few open routes. It looks only at the method, the path and the session token, so a refused
/// request's body is never read.
struct RequestGate<Next: HTTPResponder>: HTTPResponder where Next.Context == HiveRequestContext {
    typealias Context = HiveRequestContext

    struct OpenRoute: Hashable {
        let method: HTTPRequest.Method
        let path: String
    }

    static var openRoutes: Set<OpenRoute> {
        [
            OpenRoute(method: .get, path: HiveEndpoint.health),
            OpenRoute(method: .post, path: HiveEndpoint.signInChallenge),
            OpenRoute(method: .post, path: HiveEndpoint.signIn),
            // Answers only a device or a Scout holding an open window's token.
            OpenRoute(method: .post, path: HiveEndpoint.pairing),
        ]
    }

    /// Every route a Scout's session reaches, and nothing else does. Matched exactly, like the open
    /// routes, so a Scout's session can't reach a device's route by a path the router reads differently.
    static var scoutRoutes: Set<OpenRoute> {
        [
            OpenRoute(method: .get, path: ScoutEndpoint.session),
        ]
    }

    private static var logger: Logger {
        Logger(subsystem: HiveLog.subsystem, category: "APIServer")
    }

    let next: Next
    let sessions: SessionStore
    let now: @Sendable () -> Date

    // Hummingbird's responders run concurrently. Matching them lets the context pass to the next one.
    @concurrent func respond(to request: Request, context: Context) async throws -> Response {
        // The router matches on this same path string, so an open route can't reach any other handler.
        if Self.openRoutes.contains(OpenRoute(method: request.method, path: request.uri.path)) {
            return try await next.respond(to: request, context: context)
        }

        guard let token = Self.bearerToken(in: request.headers),
              let owner = sessions.owner(forToken: token, at: now())
        else {
            Self.logger.debug("Refused a request that isn't signed in")
            return Response(status: .unauthorized)
        }

        var context = context
        context.sessionToken = token
        switch owner {
        case .device(let deviceID):
            guard !Self.isScoutRoute(request.uri.path) else {
                Self.logger.error("Refused a device's session on a Scout's route")
                return Response(status: .forbidden)
            }
            context.signedInDeviceID = deviceID
        case .scout(let scout):
            guard Self.scoutRoutes.contains(OpenRoute(method: request.method, path: request.uri.path)) else {
                Self.logger.error("Refused a Scout's session on a device's route")
                return Response(status: .forbidden)
            }
            context.signedInScout = scout
        }
        return try await next.respond(to: request, context: context)
    }

    /// Ignoring empty parts, so `//scout/session` counts too. A path that only decodes to one, such as
    /// `/%73cout/session`, doesn't, but a Scout's route refuses a device's session itself.
    static func isScoutRoute(_ path: String) -> Bool {
        path.split(separator: "/").first == Substring(ScoutEndpoint.routePrefix)
    }

    private static func bearerToken(in headers: HTTPFields) -> String? {
        let prefix = "Bearer "
        guard let value = headers[.authorization], value.hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }
}
