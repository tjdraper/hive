import Foundation

public struct HiveAddress: Codable, Hashable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// The path may end in a query, such as `/audit-log?before=12`.
    func url(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        // An IPv6 address only stays one host in a URL when it's in brackets.
        components.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components.port = port
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components.path = String(parts[0])
        if parts.count == 2 { components.query = String(parts[1]) }
        return components.url
    }
}
