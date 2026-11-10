import Foundation
import HiveKit
import Hummingbird

/// A change Hive won't make without a confirmation, or a confirmation it won't accept. Thrown from
/// inside a store's write transaction, it rolls the change back, and Hummingbird answers with it.
enum ConfirmationError: Error, Equatable, HTTPResponseError {
    /// 428, with why, so Beekeeper can ask the person and send the request again confirmed.
    case required(Set<ConfirmationReason>)
    /// 403. Nothing was changed.
    case refused(ConfirmationRefusalReason)

    var status: HTTPResponse.Status {
        switch self {
        case .required: .preconditionRequired
        case .refused: .forbidden
        }
    }

    func response(from request: Request, context: some RequestContext) throws -> Response {
        let answer = switch self {
        case .required(let reasons):
            try JSONResponse(ConfirmationRequired(reasons: reasons.sorted { $0.rawValue < $1.rawValue }), status: status)
        case .refused(let reason):
            try JSONResponse(ConfirmationRefusal(reason: reason), status: status)
        }
        return try answer.response(from: request, context: context)
    }
}
