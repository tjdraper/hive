import Foundation
import HiveKit
import Hummingbird
import ScoutProtocol

/// The challenge and sign-in endpoints, which the gate lets through without signing in. Devices and
/// Scouts share them, each signing a statement of its own.
enum SignInRoutes {
    /// Far more than a sign-in needs, so a stranger can't make Hive read a large body.
    static let largestBody = 4096

    static func add(to router: Router<HiveRequestContext>, workflow: SignInWorkflow, scouts: ScoutSignInWorkflow) {
        router.post(RouterPath(HiveEndpoint.signInChallenge)) { _, _ in
            try JSONResponse(workflow.issueChallenge())
        }

        router.post(RouterPath(HiveEndpoint.signIn)) { request, context in
            let body = Data(try await request.body.collect(upTo: largestBody).readableBytesView)
            if let scoutRequest = try? JSONDecoder().decode(ScoutSignInRequest.self, from: body) {
                return try answer(scouts.signIn(scoutRequest, from: ClientAddress(context.remoteAddress)))
            }
            let signInRequest = try? JSONDecoder().decode(SignInRequest.self, from: body)

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

    private static func answer(_ outcome: ScoutSignInOutcome) throws -> JSONResponse {
        switch outcome {
        case .signedIn(let token, _):
            try JSONResponse(ScoutSession(token: token, expiresInSeconds: Int(SessionStore.lifetime)))
        case .refused:
            JSONResponse(status: .unauthorized)
        case .lockedOut:
            JSONResponse(status: .tooManyRequests)
        case .incompatible:
            try JSONResponse(ScoutProtocolMismatch(hiveProtocolVersion: ScoutProtocolVersion.current), status: .conflict)
        }
    }
}
