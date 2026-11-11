import CryptoKit
import Foundation
import HiveKit
import Hummingbird

enum RecoveryKeyRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: RecoveryKeyWorkflow, confirmations: ConfirmationVerifier) {
        router.get(RouterPath(HiveEndpoint.recoveryKey)) { _, _ in
            try JSONResponse(workflow.state())
        }

        // Every paired device keeps a copy (§14). It holds every secret, but only the recovery key opens
        // it, and Hive never has that.
        router.get(RouterPath(HiveEndpoint.recoveryFile)) { _, _ in
            guard let file = try await workflow.files.currentFile() else { return JSONResponse(status: .notFound) }
            return try JSONResponse(RecoveryFileDownload(file: file))
        }

        router.put(RouterPath(HiveEndpoint.recoveryKey)) { request, context in
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            let change = try confirmed.decode(RecoveryKeyChange.self)
            guard let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: change.publicKey) else {
                throw HTTPError(.badRequest)
            }
            return try JSONResponse(await workflow.save(key, isConfirmed: confirmed.isConfirmed, by: context.requireDevice()))
        }
    }
}
