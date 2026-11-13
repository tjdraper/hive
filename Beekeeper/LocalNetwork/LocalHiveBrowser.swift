import dnssd
import Foundation
import HiveKit
import os

/// Finds Hives advertising themselves on the local network (`LocalNetworkService`), and where each can
/// be reached there. What it finds is only somewhere to try: `HiveConnection` still requires the key
/// this device pinned, and anything on the network can advertise any Hive ID.
@Observable
final class LocalHiveBrowser {
    private static let logger = Logger(subsystem: BeekeeperLog.subsystem, category: "LocalNetwork")

    /// One advertisement, as mDNSResponder names it on one interface.
    private struct Service: Hashable {
        let name: String
        let domain: String
        let interface: UInt32
    }

    private struct Found {
        let hiveID: UUID
        let address: HiveAddress
    }

    /// Told whenever the addresses found for any Hive change.
    var onChange: (() -> Void)?

    private var found: [Service: Found] = [:]
    private var browsing: DNSServiceRef?
    private var resolving: [Service: DNSServiceRef] = [:]

    /// Where the Hive was found, in no particular order. Empty when it wasn't.
    func addresses(for hiveID: UUID) -> [HiveAddress] {
        var addresses: [HiveAddress] = []
        for found in found.values where found.hiveID == hiveID && !addresses.contains(found.address) {
            addresses.append(found.address)
        }
        return addresses.sorted { ($0.host, $0.port) < ($1.host, $1.port) }
    }

    /// Browses from now on. The first time, iOS and macOS ask for local network access.
    func start() {
        guard browsing == nil else { return }
        var reference: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let error = DNSServiceBrowse(&reference, 0, 0, LocalNetworkService.type, nil, Self.browseReply, context)
        guard error == kDNSServiceErr_NoError, let reference else {
            Self.logger.error("Couldn't browse the local network: \(error, privacy: .public)")
            return
        }
        DNSServiceSetDispatchQueue(reference, .main)
        browsing = reference
        Self.logger.notice("Browsing the local network for Hives")
    }

    private func serviceAppeared(_ service: Service) {
        guard resolving[service] == nil else { return }
        var reference: DNSServiceRef?
        let context = Unmanaged.passRetained(Resolution(browser: self, service: service)).toOpaque()
        let error = DNSServiceResolve(
            &reference, 0, service.interface, service.name, LocalNetworkService.type, service.domain, Self.resolveReply, context
        )
        guard error == kDNSServiceErr_NoError, let reference else {
            Unmanaged<Resolution>.fromOpaque(context).release()
            Self.logger.error("Couldn't look up a Hive found on the local network: \(error, privacy: .public)")
            return
        }
        DNSServiceSetDispatchQueue(reference, .main)
        resolving[service] = reference
    }

    private func serviceWentAway(_ service: Service) {
        if let reference = resolving.removeValue(forKey: service) { DNSServiceRefDeallocate(reference) }
        if found.removeValue(forKey: service) != nil {
            Self.logger.notice("A Hive's advertisement on the local network went away")
            onChange?()
        }
    }

    /// The lookup is stopped once it answers, since an advertisement that changes is removed and added again.
    private func resolved(_ service: Service, host: String, port: Int, txt: Data) {
        if let reference = resolving.removeValue(forKey: service) { DNSServiceRefDeallocate(reference) }
        guard let hiveID = LocalNetworkService.hiveID(inTXTRecord: txt), port > 0 else { return }
        let trimmedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        found[service] = Found(hiveID: hiveID, address: HiveAddress(host: trimmedHost, port: port))
        Self.logger.notice("Found a Hive on the local network")
        onChange?()
    }

    /// Carries which advertisement a lookup is for into its reply.
    private final class Resolution {
        weak var browser: LocalHiveBrowser?
        let service: Service

        init(browser: LocalHiveBrowser, service: Service) {
            self.browser = browser
            self.service = service
        }
    }

    // Both replies arrive on the main queue, which `DNSServiceSetDispatchQueue` was given.

    private static let browseReply: DNSServiceBrowseReply = { _, flags, interface, error, name, _, domain, context in
        guard error == kDNSServiceErr_NoError, let name, let domain, let context else { return }
        let service = Service(name: String(cString: name), domain: String(cString: domain), interface: interface)
        let isAdded = flags & kDNSServiceFlagsAdd != 0
        let browser = Unmanaged<LocalHiveBrowser>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            if isAdded {
                browser.serviceAppeared(service)
            } else {
                browser.serviceWentAway(service)
            }
        }
    }

    private static let resolveReply: DNSServiceResolveReply = { _, _, _, error, _, host, port, txtLength, txt, context in
        guard let context else { return }
        let hostName = host.map { String(cString: $0) }
        let txtData = txt.map { Data(bytes: $0, count: Int(txtLength)) } ?? Data()
        let portNumber = Int(UInt16(bigEndian: port))
        let resolution = Unmanaged<Resolution>.fromOpaque(context).takeRetainedValue()
        MainActor.assumeIsolated {
            guard let browser = resolution.browser else { return }
            guard error == kDNSServiceErr_NoError, let hostName else {
                if let reference = browser.resolving.removeValue(forKey: resolution.service) { DNSServiceRefDeallocate(reference) }
                return
            }
            browser.resolved(resolution.service, host: hostName, port: portNumber, txt: txtData)
        }
    }
}
