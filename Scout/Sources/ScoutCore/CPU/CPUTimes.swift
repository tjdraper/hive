import ScoutProtocol

/// The time all cores together have spent each way since the server started, in clock ticks, and how
/// many cores there are, from `/proc/stat`
/// (https://www.kernel.org/doc/html/latest/filesystems/proc.html#miscellaneous-kernel-statistics-in-proc-stat).
struct CPUTimes: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var ioWait: UInt64
    var steal: UInt64
    var cores: Int

    init(user: UInt64, system: UInt64, idle: UInt64, ioWait: UInt64, steal: UInt64, cores: Int) {
        self.user = user
        self.system = system
        self.idle = idle
        self.ioWait = ioWait
        self.steal = steal
        self.cores = cores
    }

    /// The first line adds up every core: `cpu user nice system idle iowait irq softirq steal guest
    /// guest_nice`. Each core has a line of its own after it. Guest time is already counted in user time.
    init?(parsing text: String) {
        var totals: [UInt64]?
        var cores = 0
        for line in text.lines where line.hasPrefix("cpu") {
            let fields = line.split(byte: " ")
            if fields[0] == "cpu" {
                totals = fields.dropFirst().compactMap { UInt64($0) }
            } else {
                cores += 1
            }
        }
        guard let totals, totals.count >= 4, cores > 0 else { return nil }
        let field = { (index: Int) in index < totals.count ? totals[index] : 0 }
        self.init(
            user: field(0) + field(1),
            system: field(2) + field(5) + field(6),
            idle: field(3),
            ioWait: field(4),
            steal: field(7),
            cores: cores
        )
    }

    /// How the time between two readings was spent. Idle and I/O wait times can go backwards a little
    /// on some kernels, so a counter that did counts as no time.
    func use(since earlier: CPUTimes) -> CPUUse? {
        let increase = { (keyPath: KeyPath<CPUTimes, UInt64>) in
            Double(CounterIncrease.of(earlier[keyPath: keyPath], to: self[keyPath: keyPath]) ?? 0)
        }
        let user = increase(\.user)
        let system = increase(\.system)
        let ioWait = increase(\.ioWait)
        let steal = increase(\.steal)
        let total = user + system + increase(\.idle) + ioWait + steal
        guard total > 0 else { return nil }
        return CPUUse(user: user / total, system: system / total, ioWait: ioWait / total, steal: steal / total)
    }
}
