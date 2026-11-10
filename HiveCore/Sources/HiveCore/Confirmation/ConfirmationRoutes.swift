import CryptoKit
import Foundation
import HiveKit
import Hummingbird
import os

enum ConfirmationRoutes {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Confirmation")

    static func add(to router: Router<HiveRequestContext>, verifier: ConfirmationVerifier) {
        router.post(RouterPath(HiveEndpoint.confirmationChallenge)) { _, _ in
            try JSONResponse(verifier.issue())
        }

        router.put(RouterPath(HiveEndpoint.confirmationKey)) { request, context in
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: verifier, signer: .signInKey)
            // Signed by the sign-in key, so a session token on its own can't register a key.
            guard confirmed.isConfirmed else { throw ConfirmationError.refused(.malformed) }
            let registration = try confirmed.decode(ConfirmationKeyRegistration.self)
            guard let key = try? P256.Signing.PublicKey(x963Representation: registration.publicKey) else {
                throw HTTPError(.badRequest)
            }

            switch try verifier.keys.register(key.x963Representation, forDevice: context.requireDevice(), at: verifier.now()) {
            case .registered:
                logger.notice("A device registered its confirmation key")
                return JSONResponse(status: .noContent)
            case .unchanged:
                return JSONResponse(status: .noContent)
            case .refused:
                logger.error("Refused a confirmation key: the device already has another")
                throw ConfirmationError.refused(.keyAlreadyRegistered)
            case .noDevice:
                throw HTTPError(.unauthorized)
            }
        }
    }
}
