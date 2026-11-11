import Darwin
import Foundation
import HiveKit
import Synchronization
import SystemConfiguration

/// Names for the Mac's addresses and interfaces, so tests can stand in for DNS and the system's settings.
protocol HostNaming: Sendable {
    /// The name a reverse lookup gives the address, such as its MagicDNS name, or nil.
    func name(for address: String) async -> String?
    /// The Mac's Bonjour name, such as `studio.local`.
    func localHostName() -> String?
    /// What macOS calls the interface, such as Wi-Fi, or nil for one it doesn't list, such as a bridge.
    func displayName(ofInterface bsdName: String) -> String?
}

/// What each of the Mac's addresses is, so a person can tell which to choose, and the hosts another
/// device could reach Hive at, for Beekeeper to offer as address options: each address and the name a
/// reverse lookup gives it, which for a Tailscale address is its MagicDNS name, and the Mac's Bonjour
/// name. Beekeeper offers those that go with where Hive listens, as chosen before it's saved.
struct SuggestedHostResolver: Sendable {
    static let tailscale = "Tailscale"

    let naming: any HostNaming

    /// The interfaces with what they are and their addresses' names.
    func described(_ interfaces: [NetworkInterfaceAddress]) async -> [NetworkInterfaceAddress] {
        let names = await withTaskGroup(of: (String, String?).self) { group in
            for address in Set(interfaces.map(\.address)) {
                group.addTask { (address, await naming.name(for: address)) }
            }
            var names: [String: String] = [:]
            for await (address, name) in group {
                names[address] = name.flatMap(AddressOptionCheck.host)
            }
            return names
        }
        return interfaces.map { interface in
            var described = interface
            described.displayName = Self.isTailscale(interface) ? Self.tailscale : naming.displayName(ofInterface: interface.interface)
            described.hostName = names[interface.address]
            return described
        }
    }

    /// Every host Hive could suggest, each with the address it goes with. `interfaces` as `described`
    /// gives them.
    func hosts(for interfaces: [NetworkInterfaceAddress]) -> [SuggestedHost] {
        var hosts: [SuggestedHost] = []
        if let local = naming.localHostName() {
            hosts.append(SuggestedHost(host: local, label: "This Mac's name on the local network", address: nil))
        }
        for interface in interfaces {
            let label = interface.displayName ?? interface.interface
            if let name = interface.hostName {
                let nameLabel = label == Self.tailscale ? "Tailscale name" : "Name for the \(label) address"
                hosts.append(SuggestedHost(host: name, label: nameLabel, address: interface.address))
            }
            hosts.append(SuggestedHost(host: interface.address, label: label, address: interface.address))
        }
        return hosts.reduce(into: []) { unique, suggestion in
            if !unique.contains(where: { $0.host == suggestion.host }) { unique.append(suggestion) }
        }
    }

    /// Tailscale's interface is a `utun` with an address in the ranges Tailscale gives devices:
    /// 100.64.0.0/10 and fd7a:115c:a1e0::/48 (https://tailscale.com/kb/1015/100.x-addresses).
    static func isTailscale(_ interface: NetworkInterfaceAddress) -> Bool {
        guard interface.interface.hasPrefix("utun") else { return false }
        let address = interface.address
        if address.hasPrefix("fd7a:115c:a1e0:") { return true }
        let octets = address.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 100 && (64 ... 127).contains(octets[1])
    }
}

/// The system's resolver, which for a Tailscale address asks MagicDNS.
struct SystemHostNaming: HostNaming {
    /// A lookup that takes longer is left to finish on its own, so the settings never wait on DNS.
    static let lookupAllowance: TimeInterval = 2

    func name(for address: String) async -> String? {
        await withCheckedContinuation { continuation in
            let answer = ResumeOnce(continuation)
            DispatchQueue.global().async { answer.resume(Self.reverseLookup(address)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.lookupAllowance) { answer.resume(nil) }
        }
    }

    func localHostName() -> String? {
        (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
    }

    func displayName(ofInterface bsdName: String) -> String? {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let interface = interfaces.first { SCNetworkInterfaceGetBSDName($0) as String? == bsdName }
        return interface.flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? }
    }

    private static func reverseLookup(_ address: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, nil, &hints, &info) == 0, let info else { return nil }
        defer { freeaddrinfo(info) }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD) == 0 else {
            return nil
        }
        return String(validating: host.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
    }
}

/// Hands the first answer to the continuation, whichever of the lookup and its time limit comes first.
private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<String?, Never>?>

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ name: String?) {
        continuation.withLock { continuation in
            continuation?.resume(returning: name)
            continuation = nil
        }
    }
}
