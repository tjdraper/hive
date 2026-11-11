import Foundation
import HiveKit
import Hummingbird
import NIOCore

enum RestoreRoutes {
    /// A recovery file holds every server's configuration and secrets, so it can outgrow other requests.
    static let largestRequest = 4 * 1024 * 1024

    static func add(to router: Router<HiveRequestContext>, api: HiveAPI) {
        router.get(RouterPath(HiveEndpoint.restore)) { _, _ in
            try JSONResponse(api.restoreState.state())
        }

        router.post(RouterPath(HiveEndpoint.restore)) { request, context in
            let body = try await request.body.collect(upTo: largestRequest)
            guard let restore = try? JSONDecoder().decode(RestoreRequest.self, from: Data(body.readableBytesView)) else {
                throw HTTPError(.badRequest)
            }
            do {
                let outcome = try api.restore.restore(
                    restore,
                    isFromThisMac: isLoopback(context.remoteAddress),
                    by: context.requireDevice()
                )
                return try JSONResponse(outcome)
            } catch RestoreError.refused(let problem) {
                return try JSONResponse(RestoreRefusal(problem: problem), status: .unprocessableContent)
            }
        }

        router.delete(RouterPath(HiveEndpoint.retentionPause)) { request, context in
            let confirmed = try await ConfirmedRequest.read(request, context: context, verifier: api.confirmations)
            let device = try context.requireDevice()
            guard try api.retentionPause.startRetention(isConfirmed: confirmed.isConfirmed, by: device, at: api.signIn.now()) else {
                return JSONResponse(status: .notFound)
            }
            await api.runs.requestRetentionPass()
            return JSONResponse(status: .noContent)
        }
    }

    /// Only the connection's own address counts. Hive always listens on `127.0.0.1`, where Beekeeper on
    /// its Mac connects. A connection over any other interface, even from this Mac, isn't loopback.
    static func isLoopback(_ address: SocketAddress?) -> Bool {
        switch address {
        case .v4(let ipv4):
            withUnsafeBytes(of: ipv4.address.sin_addr) { $0.first == 127 }
        case .v6(let ipv6):
            withUnsafeBytes(of: ipv6.address.sin6_addr) { bytes in
                let isOne = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1
                let isMappedIPv4 = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF && bytes[12] == 127
                return isOne || isMappedIPv4
            }
        default:
            false
        }
    }
}
