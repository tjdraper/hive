import Foundation
import HiveKit
import Hummingbird

/// The challenge endpoint, which the gate lets through without signing in.
enum SignInRoutes {
    /// Far more than a sign-in needs, so a stranger can't make Hive read a large body.
    static let largestBody = 4096

    static func add(to router: Router<HiveRequestContext>, workflow: SignInWorkflow) {
        router.post(RouterPath(HiveEndpoint.signInChallenge)) { _, _ in
            try JSONResponse(workflow.issueChallenge())
        }

        router.post(RouterPath(HiveEndpoint.signIn)) { request, context in
            let body = try await request.body.collect(upTo: largestBody)
            let signInRequest = try? JSONDecoder().decode(SignInRequest.self, from: Data(body.readableBytesView))

            switch workflow.signIn(signInRequest, from: ClientAddress(context.remoteAddress)) {
            case .signedIn(let token, _):
                let session = SignInSession(
                    token: token,
                    expiresInSeconds: Int(SessionStore.lifetime),
                    hiveAPIVersions: workflow.apiVersions
                )
                return try JSONResponse(session)
            case .refused:
                return JSONResponse(status: .unauthorized)
            case .lockedOut:
                return JSONResponse(status: .tooManyRequests)
            case .incompatible(let outdated):
                return try JSONResponse(APIVersionMismatch(update: outdated, hiveAPIVersions: workflow.apiVersions), status: .conflict)
            }
        }
    }
}
