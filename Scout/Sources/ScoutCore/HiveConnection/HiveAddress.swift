/// Where Scout reaches a Hive: one of its address options and its port.
public struct HiveAddress: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// `host:port`, with an IPv6 address in brackets, such as `[fd7a:115c:a1e0::1]:4483`.
    public init?(parsing text: String) {
        guard let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]),
              (1...65_535).contains(port)
        else { return nil }
        var host = text[..<colon]
        if host.first == "[", host.last == "]" {
            host = host.dropFirst().dropLast()
        } else if host.contains(":") {
            return nil
        }
        guard !host.isEmpty else { return nil }
        self.init(host: String(host), port: port)
    }

    /// The HTTP `Host` header's form of the host.
    var hostHeader: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}
