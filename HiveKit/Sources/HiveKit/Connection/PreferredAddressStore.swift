import Foundation
import Network
import Synchronization

/// The address a Hive last answered at. It's forgotten when the device's network changes, since an
/// address on the network it left would otherwise hold up the next request until it timed out.
final class PreferredAddressStore: Sendable {
    private struct State {
        var address: HiveAddress?
        var path: NWPath?
    }

    private static let queue = DispatchQueue(label: "PreferredAddressStore.network")

    private let state = Mutex(State())
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.networkChanged(to: path) }
        monitor.start(queue: Self.queue)
    }

    deinit {
        monitor.cancel()
    }

    var address: HiveAddress? {
        state.withLock { $0.address }
    }

    func remember(_ address: HiveAddress) {
        state.withLock { $0.address = address }
    }

    /// Only while it's still `address`, so a request that failed late doesn't undo a newer one that worked.
    func forget(_ address: HiveAddress) {
        state.withLock { state in
            if state.address == address { state.address = nil }
        }
    }

    private func networkChanged(to path: NWPath) {
        state.withLock { state in
            if let previous = state.path, previous != path { state.address = nil }
            state.path = path
        }
    }
}
