import Foundation
import Hummingbird
import NIOCore

struct HiveRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    let remoteAddress: SocketAddress?
    /// Set by `RequestGate` for every request with a device's session.
    var signedInDeviceID: UUID?
    /// Set by `RequestGate` instead of `signedInDeviceID` for a Scout's session, which reaches only Scout's routes.
    var signedInScout: SignedInScout?
    /// Set with `signedInDeviceID` or `signedInScout`, for a response that outlasts the request to
    /// check it's still good.
    var sessionToken: String?

    init(source: ApplicationRequestContextSource) {
        coreContext = CoreRequestContextStorage(source: source)
        remoteAddress = source.channel.remoteAddress
    }
}
