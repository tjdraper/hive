import Foundation
import HiveKit
import Hummingbird

enum PairingRoutes {
    /// Far more than a pairing needs, so a stranger can't make Hive read a large body.
    static let largestBody = 4096

    static func add(
        to router: Router<HiveRequestContext>,
        windows: PairingWindowWorkflow,
        pairing: CodePairingWorkflow,
        confirmations: ConfirmationVerifier
    ) {
        router.post(RouterPath(HiveEndpoint.pairingWindow)) { request, context in
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: confirmations)
            do {
                return try JSONResponse(windows.open(isConfirmed: confirmed.isConfirmed, by: context.requireDevice()), status: .created)
            } catch PairingWindowError.refused(let problem) {
                return try JSONResponse(PairingWindowRefusal(problem: problem), status: .unprocessableContent)
            } catch PairingWindowError.restarting {
                return JSONResponse(status: .serviceUnavailable)
            }
        }

        router.get(RouterPath(HiveEndpoint.pairingWindow)) { _, _ in
            try JSONResponse(windows.state())
        }

        router.delete(RouterPath(HiveEndpoint.pairingWindow)) { _, context in
            try windows.close(by: context.requireDevice())
            return JSONResponse(status: .noContent)
        }

        // Open to devices that aren't signed in: the gate lets it through.
        router.post(RouterPath(HiveEndpoint.pairing)) { request, context in
            let body = try await request.body.collect(upTo: largestBody)
            let pairingRequest = try? JSONDecoder().decode(PairingRequest.self, from: Data(body.readableBytesView))

            switch pairing.pair(pairingRequest, from: ClientAddress(context.remoteAddress)) {
            case .paired(let result):
                return try JSONResponse(result)
            case .refused:
                return JSONResponse(status: .notFound)
            case .invalid(.storeUnavailable):
                return JSONResponse(status: .internalServerError)
            case .invalid:
                return JSONResponse(status: .unprocessableContent)
            case .lockedOut:
                return JSONResponse(status: .tooManyRequests)
            case .incompatible(let outdated):
                return try JSONResponse(APIVersionMismatch(update: outdated, hiveAPIVersions: pairing.apiVersions), status: .conflict)
            }
        }
    }
}
