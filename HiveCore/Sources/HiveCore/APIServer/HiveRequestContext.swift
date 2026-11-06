import Foundation
import Hummingbird
import NIOCore

struct HiveRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    let remoteAddress: SocketAddress?
    /// Set by `RequestGate` for every request that isn't to an open route.
    var signedInDeviceID: UUID?

    init(source: ApplicationRequestContextSource) {
        coreContext = CoreRequestContextStorage(source: source)
        remoteAddress = source.channel.remoteAddress
    }
}
