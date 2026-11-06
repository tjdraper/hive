import Foundation
import Hummingbird

enum JSONRequest {
    /// Far more than any request to Hive needs.
    static let largestBody = 64 * 1024

    static func decode<Value: Decodable>(_: Value.Type, from request: Request) async throws -> Value {
        let body = try await request.body.collect(upTo: largestBody)
        do {
            return try JSONDecoder().decode(Value.self, from: Data(body.readableBytesView))
        } catch {
            throw HTTPError(.badRequest)
        }
    }
}

extension HiveRequestContext {
    /// The device that sent the request. `RequestGate` sets it before any route that needs it runs.
    func requireDevice() throws -> UUID {
        guard let signedInDeviceID else { throw HTTPError(.unauthorized) }
        return signedInDeviceID
    }
}
