import Foundation
import HiveKit
import Hummingbird
import ScoutProtocol

enum PairingRoutes {
    /// Far more than a pairing needs, so a stranger can't make Hive read a large body.
    static let largestBody = 4096

    static func add(
        to router: Router<HiveRequestContext>,
        windows: PairingWindowWorkflow,
        pairing: CodePairingWorkflow,
        enrollment: ScoutEnrollmentWorkflow,
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

        // Open to devices and Scouts that aren't signed in: the gate lets it through. A Scout's request
        // goes only to Scouts' windows, and a device's only to the pairing window, so neither's token
        // opens the other's.
        router.post(RouterPath(HiveEndpoint.pairing)) { request, context in
            let body = Data(try await request.body.collect(upTo: largestBody).readableBytesView)
            let address = ClientAddress(context.remoteAddress)
            if let scoutRequest = try? JSONDecoder().decode(ScoutEnrollmentRequest.self, from: body) {
                return try answer(enrollment.enroll(scoutRequest, from: address))
            }
            let pairingRequest = try? JSONDecoder().decode(PairingRequest.self, from: body)

            switch pairing.pair(pairingRequest, from: address) {
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

    private static func answer(_ outcome: ScoutEnrollmentOutcome) throws -> JSONResponse {
        switch outcome {
        case .enrolled(let enrollment):
            try JSONResponse(enrollment)
        case .refused:
            JSONResponse(status: .notFound)
        case .invalid(.storeUnavailable):
            JSONResponse(status: .internalServerError)
        case .invalid:
            JSONResponse(status: .unprocessableContent)
        case .lockedOut:
            JSONResponse(status: .tooManyRequests)
        case .incompatible:
            try JSONResponse(ScoutProtocolMismatch(hiveProtocolVersion: ScoutProtocolVersion.current), status: .conflict)
        }
    }
}
