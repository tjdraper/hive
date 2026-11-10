import Foundation
import HiveKit
import Hummingbird

/// A request to a route whose change may need confirming: its body, as the signature covers it, and
/// whether it carried a good confirmation. Whether one was needed is the store's to decide.
struct ConfirmedRequest {
    let body: Data
    let isConfirmed: Bool

    static func read(
        _ request: Request,
        context: HiveRequestContext,
        verifier: ConfirmationVerifier,
        signer: ConfirmationVerifier.Signer = .confirmationKey
    ) async throws -> ConfirmedRequest {
        let body = Data(try await request.body.collect(upTo: JSONRequest.largestBody).readableBytesView)
        var proof: ConfirmationProof?
        // Hummingbird names `HTTPFields` but not the field type itself.
        if let name = HTTPFields.Element.Name(ConfirmationProof.headerName), let value = request.headers[name] {
            guard let parsed = ConfirmationProof(headerValue: value) else { throw ConfirmationError.refused(.malformed) }
            proof = parsed
        }
        let isConfirmed = try verifier.verify(
            proof,
            method: request.method.rawValue,
            path: request.uri.path,
            body: body,
            deviceID: context.requireDevice(),
            signer: signer
        )
        return ConfirmedRequest(body: body, isConfirmed: isConfirmed)
    }

    func decode<Value: Decodable>(_: Value.Type) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: body)
        } catch {
            throw HTTPError(.badRequest)
        }
    }
}
