import ScoutProtocol

/// Reads memory and swap, keeping the previous swap counters that swapping is worked out from.
struct MemoryReader {
    let files: SystemFiles
    private var previous: SwapCounters?

    init(files: SystemFiles) {
        self.files = files
    }

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> MemoryFigures? {
        guard let info = files.text(at: "/proc/meminfo").flatMap(MemoryInfo.init(parsing:)) else { return nil }
        let counters = files.text(at: "/proc/vmstat").flatMap(SwapCounters.init(parsing:))
        defer { previous = counters }
        return MemoryFigures(
            totalBytes: info.total,
            availableBytes: info.available,
            cacheBytes: info.cache,
            swapTotalBytes: info.swapTotal,
            swapUsedBytes: info.swapTotal - min(info.swapFree, info.swapTotal),
            swapping: Self.swapping(from: previous, to: counters, seconds: elapsed)
        )
    }

    static func swapping(from previous: SwapCounters?, to current: SwapCounters?, seconds: Double?) -> Swapping? {
        guard let previous, let current, let seconds,
              let pagesIn = CounterIncrease.perSecond(previous.pagesIn, to: current.pagesIn, seconds: seconds),
              let pagesOut = CounterIncrease.perSecond(previous.pagesOut, to: current.pagesOut, seconds: seconds)
        else { return nil }
        return Swapping(pagesInPerSecond: pagesIn, pagesOutPerSecond: pagesOut)
    }
}
