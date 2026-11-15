#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import NIOCore

enum HostLookupError: Error {
    case unknownHost(code: Int32)
    case noAddresses
}

/// Every address a host name stands for, in the order the system gives them, since a name such as
/// `localhost` can stand for an IPv6 address Hive doesn't listen on as well as an IPv4 one it does.
/// It blocks, so it runs on ``ScoutEventLoop``'s lookup thread.
enum HostLookup {
    static func addresses(of address: HiveAddress) throws -> [SocketAddress] {
        // Without hints, glibc adds AI_ADDRCONFIG, which refuses even an IPv6 address written out in
        // full on a server with no IPv6 address of its own. Each address is tried in turn anyway.
        var hints = addrinfo()
        #if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        var first: UnsafeMutablePointer<addrinfo>?
        let code = getaddrinfo(address.host, String(address.port), &hints, &first)
        guard code == 0 else { throw HostLookupError.unknownHost(code: code) }
        defer { freeaddrinfo(first) }

        var addresses: [SocketAddress] = []
        var next = first
        while let entry = next?.pointee {
            next = entry.ai_next
            guard let found = socketAddress(entry, host: address.host), !addresses.contains(found) else { continue }
            addresses.append(found)
        }
        guard !addresses.isEmpty else { throw HostLookupError.noAddresses }
        return addresses
    }

    private static func socketAddress(_ entry: addrinfo, host: String) -> SocketAddress? {
        guard let raw = entry.ai_addr.map(UnsafeRawPointer.init) else { return nil }
        switch entry.ai_family {
        case AF_INET: return SocketAddress(raw.loadUnaligned(as: sockaddr_in.self), host: host)
        case AF_INET6: return SocketAddress(raw.loadUnaligned(as: sockaddr_in6.self), host: host)
        default: return nil
        }
    }
}
