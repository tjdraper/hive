import Foundation

public struct HiveAddress: Hashable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func url(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        // An IPv6 address only stays one host in a URL when it's in brackets.
        components.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components.port = port
        components.path = path
        return components.url
    }
}
