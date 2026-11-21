import Foundation
import Hummingbird
import NIOCore
import ScoutProtocol

/// The route Scouts send figures to. `RequestGate` lets only a Scout's session reach it.
enum MetricsRoutes {
    static func add(to router: Router<HiveRequestContext>, workflow: MetricsReportWorkflow) {
        router.post(RouterPath(ScoutEndpoint.metrics)) { request, context in
            let serverID = try context.requireScout().serverID
            guard workflow.admits(serverID) else { return JSONResponse(status: .tooManyRequests) }

            let body: Data
            do {
                body = Data(try await request.body.collect(upTo: MetricsReportCheck.largestBody).readableBytesView)
            } catch is NIOTooManyBytesError {
                return try response(for: workflow.refuse(.tooLarge, forServer: serverID))
            }
            return try response(for: workflow.keep(body, forServer: serverID))
        }
    }

    private static func response(for outcome: MetricsReportOutcome) throws -> JSONResponse {
        switch outcome {
        case .kept:
            JSONResponse(status: .noContent)
        case .refused(let reason):
            try JSONResponse(ScoutRefusal(reason: reason), status: .unprocessableContent)
        case .protocolNotAccepted:
            try JSONResponse(ScoutProtocolMismatch(hiveProtocolVersion: ScoutProtocolVersion.current), status: .conflict)
        case .unavailable:
            JSONResponse(status: .serviceUnavailable)
        }
    }
}
