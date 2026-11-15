/// What a server is, sent with every sample so a reboot or an upgrade shows as soon as it happens.
public struct ServerFacts: Codable, Hashable, Sendable {
    public var uptimeSeconds: Double?
    /// `PRETTY_NAME` from `/etc/os-release`, such as "Debian GNU/Linux 12 (bookworm)".
    public var distribution: String?
    public var kernel: String?
    public var scoutVersion: String

    public init(uptimeSeconds: Double?, distribution: String?, kernel: String?, scoutVersion: String) {
        self.uptimeSeconds = uptimeSeconds
        self.distribution = distribution
        self.kernel = kernel
        self.scoutVersion = scoutVersion
    }
}
