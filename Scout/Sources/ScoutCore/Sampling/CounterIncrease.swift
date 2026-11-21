/// How much one of the kernel's counters grew between two readings.
enum CounterIncrease {
    /// For a counter the kernel keeps in 64 bits, which never wraps in practice. Nil when it went
    /// backwards, as an interface's counters do when it's recreated, since how much it grew can't be known.
    static func of(_ previous: UInt64, to current: UInt64) -> UInt64? {
        current >= previous ? current - previous : nil
    }

    /// For a counter the kernel keeps in 32 bits, such as a disk's milliseconds busy, which wraps
    /// after 49.7 days of use. Going backwards is taken as a wrap.
    static func of32Bit(_ previous: UInt64, to current: UInt64) -> UInt64 {
        (current &- previous) & 0xFFFF_FFFF
    }

    /// A count per second, or nil when the counter went backwards.
    static func perSecond(_ previous: UInt64, to current: UInt64, seconds: Double) -> Double? {
        of(previous, to: current).map { Double($0) / seconds }
    }
}
