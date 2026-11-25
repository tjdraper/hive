#if os(macOS)
import Darwin
import ScoutProtocol

/// The time every core together has spent each way since the Mac started, in clock ticks, from
/// `host_statistics`' `HOST_CPU_LOAD_INFO`. The kernel keeps each in 32 bits, so they wrap.
struct MacCPUTicks: Equatable {
    var user: UInt64
    var nice: UInt64
    var system: UInt64
    var idle: UInt64

    /// A Mac counts no I/O wait, which is idle there, and no steal, so both are left out rather than
    /// given as nothing.
    func use(since earlier: MacCPUTicks) -> CPUUse? {
        let increase = { (keyPath: KeyPath<MacCPUTicks, UInt64>) in
            Double(CounterIncrease.of32Bit(earlier[keyPath: keyPath], to: self[keyPath: keyPath]))
        }
        let user = increase(\.user) + increase(\.nice)
        let system = increase(\.system)
        let total = user + system + increase(\.idle)
        guard total > 0 else { return nil }
        return CPUUse(user: user / total, system: system / total, ioWait: nil, steal: nil)
    }

    static func read() -> MacCPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(MacSysctl.host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        // In `CPU_STATE_USER`, `CPU_STATE_SYSTEM`, `CPU_STATE_IDLE` and `CPU_STATE_NICE` order.
        return MacCPUTicks(user: UInt64(ticks.0), nice: UInt64(ticks.3), system: UInt64(ticks.1), idle: UInt64(ticks.2))
    }
}

/// Reads how busy a Mac's CPU is and its load, keeping the previous reading that use is worked out from.
struct MacCPUReader {
    private var previous: MacCPUTicks?

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> CPUFigures? {
        guard let ticks = MacCPUTicks.read(), let cores = MacSysctl.value("hw.logicalcpu", as: Int32.self) else { return nil }
        defer { previous = ticks }
        let use = elapsed == nil ? nil : previous.flatMap { ticks.use(since: $0) }
        return CPUFigures(cores: Int(cores), use: use, load: Self.loadAverages())
    }

    private static func loadAverages() -> LoadAverages? {
        var averages = [Double](repeating: 0, count: 3)
        guard getloadavg(&averages, 3) == 3 else { return nil }
        return LoadAverages(oneMinute: averages[0], fiveMinutes: averages[1], fifteenMinutes: averages[2])
    }
}
#endif
