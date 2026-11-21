import ScoutProtocol

/// Reads each real network interface's traffic, keeping the previous counters it's worked out from.
struct NetworkReader {
    let files: SystemFiles
    private var previous: [String: InterfaceCounters] = [:]

    init(files: SystemFiles) {
        self.files = files
    }

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> [NetworkInterfaceFigures] {
        let interfaces = (files.text(at: "/proc/net/dev").map(InterfaceCounters.all(parsing:)) ?? [])
            .filter { Self.isReported($0.name) }
            .sorted { $0.name < $1.name }
        defer { previous = Dictionary(interfaces.map { ($0.name, $0) }) { first, _ in first } }
        return interfaces.map { interface in
            let traffic = elapsed.flatMap { seconds in
                previous[interface.name].flatMap { Self.traffic(from: $0, to: interface, seconds: seconds) }
            }
            return NetworkInterfaceFigures(name: interface.name, traffic: traffic)
        }
    }

    /// Loopback, and the interfaces Docker makes: its bridges and one end of each container's link
    /// to them, whose traffic the real interfaces count too. Tunnels such as `tailscale0` and
    /// `wg0` are virtual but carry real traffic, so they're kept, as are bridges named by hand.
    static func isReported(_ name: String) -> Bool {
        if name == "lo" || name.hasPrefix("docker") || name.hasPrefix("veth") { return false }
        let dockerNetworkID = name.dropFirst("br-".count)
        return !(name.hasPrefix("br-") && dockerNetworkID.count == 12 && dockerNetworkID.allSatisfy(\.isHexDigit))
    }

    /// Nil when a counter went backwards, as when an interface is recreated with the same name.
    static func traffic(from earlier: InterfaceCounters, to current: InterfaceCounters, seconds: Double) -> NetworkTraffic? {
        let rate = { (keyPath: KeyPath<InterfaceCounters, UInt64>) in
            CounterIncrease.perSecond(earlier[keyPath: keyPath], to: current[keyPath: keyPath], seconds: seconds)
        }
        guard let received = rate(\.receivedBytes), let sent = rate(\.sentBytes),
              let receiveErrors = rate(\.receiveErrors), let sendErrors = rate(\.sendErrors),
              let receiveDrops = rate(\.receiveDrops), let sendDrops = rate(\.sendDrops)
        else { return nil }
        return NetworkTraffic(
            receivedBytesPerSecond: received,
            sentBytesPerSecond: sent,
            receiveErrorsPerSecond: receiveErrors,
            sendErrorsPerSecond: sendErrors,
            receiveDropsPerSecond: receiveDrops,
            sendDropsPerSecond: sendDrops
        )
    }
}
