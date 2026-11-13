import dnssd
import Foundation
import HiveKit
import os
import Synchronization

/// Advertises the Hive through mDNSResponder, with one registration for each interface. Registering
/// on every interface at once would include Tailscale's, which is multicast-capable like any other.
final class BonjourAdvertiser: LocalNetworkAdvertiser {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Advertising")

    private struct State: ~Copyable {
        var advertised: LocalNetworkAdvertisement?
        var registrations: [UInt32: DNSServiceRef] = [:]
    }

    private let state = Mutex(State())
    /// Each registration's results arrive here, and mDNSResponder requires it to be deallocated here too.
    private let queue = DispatchQueue(label: "Hive.BonjourAdvertiser")

    func advertise(_ advertisement: LocalNetworkAdvertisement?) {
        queue.async { [self] in
            state.withLock { update(&$0, to: advertisement) }
        }
    }

    /// A registration that failed is tried again the next time the listeners are checked.
    private func update(_ state: inout State, to advertisement: LocalNetworkAdvertisement?) {
        let wanted = advertisement?.interfaces ?? []
        guard state.advertised != advertisement || Set(state.registrations.keys) != wanted else { return }
        let sameService = state.advertised?.hive == advertisement?.hive && state.advertised?.port == advertisement?.port
        let keep = sameService ? wanted : []

        for (index, registration) in state.registrations where !keep.contains(index) {
            DNSServiceRefDeallocate(registration)
            state.registrations[index] = nil
        }
        if let advertisement {
            for index in wanted where state.registrations[index] == nil {
                state.registrations[index] = register(advertisement, on: index)
            }
        }
        if state.advertised != advertisement {
            let count = state.registrations.count
            Self.logger.notice("Advertising on \(count, privacy: .public) local networks")
        }
        state.advertised = advertisement
    }

    private func register(_ advertisement: LocalNetworkAdvertisement, on index: UInt32) -> DNSServiceRef? {
        let name = LocalNetworkService.instanceName(for: advertisement.hive.name)
        let txt = LocalNetworkService.txtRecord(hiveID: advertisement.hive.hiveID)
        var reference: DNSServiceRef?
        let error = txt.withUnsafeBytes { bytes in
            DNSServiceRegister(
                &reference,
                0,
                index,
                name,
                LocalNetworkService.type,
                nil,
                nil,
                UInt16(advertisement.port).bigEndian,
                UInt16(bytes.count),
                bytes.baseAddress,
                { _, _, error, _, _, _, _ in
                    if error != kDNSServiceErr_NoError {
                        BonjourAdvertiser.logger.error("An advertisement failed: \(error, privacy: .public)")
                    }
                },
                nil
            )
        }
        guard error == kDNSServiceErr_NoError, let reference else {
            Self.logger.error("Couldn't advertise on a local network: \(error, privacy: .public)")
            return nil
        }
        DNSServiceSetDispatchQueue(reference, queue)
        return reference
    }
}
