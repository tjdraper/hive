#if os(macOS)
import Darwin
import ScoutProtocol

/// The parts of `host_statistics64`' `HOST_VM_INFO64` and `vm.swapusage` Scout uses, with memory
/// counted as Activity Monitor counts it, so the two agree.
struct MacMemoryCounts: Equatable {
    var pageSize: UInt64
    var totalBytes: UInt64
    var wiredPages: UInt64
    /// Pages the compressor holds, of compressed memory.
    var compressedPages: UInt64
    /// Pages of anonymous memory, and those of files.
    var internalPages: UInt64
    var externalPages: UInt64
    /// Pages an app marked as free to drop, counted among the internal ones.
    var purgeablePages: UInt64
    var swapIns: UInt64
    var swapOuts: UInt64
    var swapTotalBytes: UInt64
    var swapUsedBytes: UInt64

    /// Activity Monitor's App Memory, Wired Memory and Compressed together: its Memory Used.
    var usedBytes: UInt64 {
        let appPages = internalPages - min(purgeablePages, internalPages)
        return min((appPages + wiredPages + compressedPages) * pageSize, totalBytes)
    }

    /// Available is everything not in use, as for Linux's `MemAvailable`: free memory and what can be
    /// dropped, which Activity Monitor calls Cached Files.
    func figures(swapping: Swapping?) -> MemoryFigures {
        MemoryFigures(
            totalBytes: totalBytes,
            availableBytes: totalBytes - usedBytes,
            cacheBytes: (externalPages + purgeablePages) * pageSize,
            swapTotalBytes: swapTotalBytes,
            swapUsedBytes: min(swapUsedBytes, swapTotalBytes),
            swapping: swapping
        )
    }

    static func read() -> MacMemoryCounts? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(MacSysctl.host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(MacSysctl.host, &pageSize) == KERN_SUCCESS,
              let total = MacSysctl.value("hw.memsize", as: UInt64.self)
        else { return nil }
        let swap = MacSysctl.value("vm.swapusage", as: xsw_usage.self)
        return MacMemoryCounts(
            pageSize: UInt64(pageSize),
            totalBytes: total,
            wiredPages: UInt64(statistics.wire_count),
            compressedPages: UInt64(statistics.compressor_page_count),
            internalPages: UInt64(statistics.internal_page_count),
            externalPages: UInt64(statistics.external_page_count),
            purgeablePages: UInt64(statistics.purgeable_count),
            swapIns: statistics.swapins,
            swapOuts: statistics.swapouts,
            swapTotalBytes: swap?.xsu_total ?? 0,
            swapUsedBytes: swap?.xsu_used ?? 0
        )
    }
}

/// Reads a Mac's memory and swap, keeping the previous counts swapping is worked out from.
struct MacMemoryReader {
    private var previous: MacMemoryCounts?

    mutating func read(elapsed: Double?) -> MemoryFigures? {
        guard let counts = MacMemoryCounts.read() else { return nil }
        defer { previous = counts }
        let swapping = MemoryReader.swapping(
            from: previous.map { SwapCounters(pagesIn: $0.swapIns, pagesOut: $0.swapOuts) },
            to: SwapCounters(pagesIn: counts.swapIns, pagesOut: counts.swapOuts),
            seconds: elapsed
        )
        return counts.figures(swapping: swapping)
    }
}
#endif
