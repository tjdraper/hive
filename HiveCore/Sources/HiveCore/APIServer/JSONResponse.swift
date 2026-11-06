import Foundation
import Hummingbird

/// A response with a JSON body, or none. HiveKit's message types are encoded here rather than made
/// `ResponseEncodable`, which would be a conformance of another module's type to another module's protocol.
struct JSONResponse: ResponseGenerator {
    let status: HTTPResponse.Status
    let body: Data?

    init(status: HTTPResponse.Status) {
        self.status = status
        body = nil
    }

    init(_ value: some Encodable, status: HTTPResponse.Status = .ok) throws {
        self.status = status
        body = try JSONEncoder().encode(value)
    }

    func response(from _: Request, context _: some RequestContext) throws -> Response {
        guard let body else { return Response(status: status) }
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}
