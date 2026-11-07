import Darwin
import Foundation

/// The addresses a server's host name resolves to, in the order the system gives them.
enum HostAddressResolver {
    /// Empty when the name doesn't resolve. A numeric address resolves to itself.
    static func addresses(of host: String) async -> [String] {
        // getaddrinfo blocks for as long as a DNS lookup takes, which mustn't hold a thread of Swift's pool.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: resolve(host))
            }
        }
    }

    private static func resolve(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var first: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &first) == 0 else { return [] }
        defer { freeaddrinfo(first) }

        var found: [String] = []
        for entry in sequence(first: first, next: { $0?.pointee.ai_next }) {
            guard let entry = entry?.pointee, let address = numeric(entry), !found.contains(address) else { continue }
            found.append(address)
        }
        return found
    }

    private static func numeric(_ entry: addrinfo) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(entry.ai_addr, entry.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}
