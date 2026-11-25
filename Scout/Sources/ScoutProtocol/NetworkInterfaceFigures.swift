/// A network interface, such as `eth0` or `tailscale0`. Loopback and Docker's virtual interfaces aren't sent.
public struct NetworkInterfaceFigures: Codable, Hashable, Sendable {
    public var name: String
    /// Missing from the first sample, and when the interface's counters started again, as they do
    /// when it's recreated.
    public var traffic: NetworkTraffic?

    public init(name: String, traffic: NetworkTraffic?) {
        self.name = name
        self.traffic = traffic
    }
}

/// Since the previous sample.
public struct NetworkTraffic: Codable, Hashable, Sendable {
    public var receivedBytesPerSecond: Double
    public var sentBytesPerSecond: Double
    public var receiveErrorsPerSecond: Double
    public var sendErrorsPerSecond: Double
    public var receiveDropsPerSecond: Double
    /// Missing on a Mac, which doesn't count them for each interface.
    public var sendDropsPerSecond: Double?

    public init(
        receivedBytesPerSecond: Double,
        sentBytesPerSecond: Double,
        receiveErrorsPerSecond: Double,
        sendErrorsPerSecond: Double,
        receiveDropsPerSecond: Double,
        sendDropsPerSecond: Double?
    ) {
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
        self.receiveErrorsPerSecond = receiveErrorsPerSecond
        self.sendErrorsPerSecond = sendErrorsPerSecond
        self.receiveDropsPerSecond = receiveDropsPerSecond
        self.sendDropsPerSecond = sendDropsPerSecond
    }
}
