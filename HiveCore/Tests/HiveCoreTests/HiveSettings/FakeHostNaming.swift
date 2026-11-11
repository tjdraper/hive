@testable import HiveCore
import Synchronization

/// Names for the Mac's addresses and interfaces, as DNS and the system would give them, without asking either.
final class FakeHostNaming: HostNaming {
    private let names = Mutex(["100.64.0.7": "studio.tail0000.ts.net."])

    func set(_ new: [String: String]) {
        names.withLock { $0 = new }
    }

    func name(for address: String) async -> String? {
        names.withLock { $0[address] }
    }

    func localHostName() -> String? {
        "studio.local"
    }

    func displayName(ofInterface bsdName: String) -> String? {
        ["en0": "Wi-Fi", "utun4": "Some VPN"][bsdName]
    }
}
