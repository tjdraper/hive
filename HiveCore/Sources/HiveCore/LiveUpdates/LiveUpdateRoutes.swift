import Foundation
import HiveKit
import Hummingbird
import os

enum LiveUpdateRoutes {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "LiveUpdates")
    /// Without it, URLSession holds back the first bytes of a response to guess their type.
    private static let contentTypeOptions = HTTPFields.Element.Name("X-Content-Type-Options")

    static func add(
        to router: Router<HiveRequestContext>,
        stream: LiveUpdateStream,
        signIn: SignInWorkflow
    ) {
        router.get(RouterPath(HiveEndpoint.liveUpdates)) { _, context in
            guard let token = context.sessionToken else { throw HTTPError(.unauthorized) }
            let isSignedIn: @Sendable () -> Bool = { signIn.sessions.deviceID(forToken: token, at: signIn.now()) != nil }
            var headers: HTTPFields = [.contentType: "application/x-ndjson", .cacheControl: "no-store"]
            if let contentTypeOptions { headers[contentTypeOptions] = "nosniff" }
            return Response(
                status: .ok,
                headers: headers,
                body: ResponseBody { writer in
                    let started = ContinuousClock.now
                    logger.info("A device started live updates")
                    do {
                        let ending = try await stream.run(isSignedIn: isSignedIn, writing: { update in
                            var line = try JSONEncoder().encode(update)
                            line.append(UInt8(ascii: "\n"))
                            try await writer.write(ByteBuffer(bytes: line))
                        })
                        let seconds = (ContinuousClock.now - started).roundedSeconds
                        logger.info("Live updates ended: \(ending.rawValue, privacy: .public) after \(seconds, privacy: .public)s")
                    } catch {
                        logger.info("Live updates ended on \(String(describing: type(of: error)), privacy: .public)")
                        throw error
                    }
                    try await writer.finish(nil)
                }
            )
        }
    }
}
