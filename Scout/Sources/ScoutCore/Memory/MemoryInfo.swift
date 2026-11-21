/// The parts of `/proc/meminfo` Scout uses, in bytes. Its lines are `Name: value kB`, and kB there
/// means 1024 bytes.
struct MemoryInfo: Equatable {
    var total: UInt64
    var available: UInt64
    var cache: UInt64
    var swapTotal: UInt64
    var swapFree: UInt64

    init?(parsing text: String) {
        var values: [Substring: UInt64] = [:]
        for line in text.lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let number = line[line.index(after: colon)...].split(byte: " ").first.flatMap { UInt64($0) }
            values[line[..<colon]] = number.map { $0 * 1024 }
        }
        guard let total = values["MemTotal"], let available = values["MemAvailable"] else { return nil }
        self.total = total
        self.available = available
        // What `free` shows as buff/cache.
        cache = (values["Buffers"] ?? 0) + (values["Cached"] ?? 0) + (values["SReclaimable"] ?? 0)
        swapTotal = values["SwapTotal"] ?? 0
        swapFree = values["SwapFree"] ?? 0
    }
}

/// Pages swapped in and out since the server started, from `/proc/vmstat`'s `name value` lines.
struct SwapCounters: Equatable {
    var pagesIn: UInt64
    var pagesOut: UInt64

    init(pagesIn: UInt64, pagesOut: UInt64) {
        self.pagesIn = pagesIn
        self.pagesOut = pagesOut
    }

    init?(parsing text: String) {
        var pagesIn: UInt64?
        var pagesOut: UInt64?
        for line in text.lines where line.hasPrefix("pswp") {
            let fields = line.split(byte: " ")
            guard fields.count == 2 else { continue }
            switch fields[0] {
            case "pswpin": pagesIn = UInt64(fields[1])
            case "pswpout": pagesOut = UInt64(fields[1])
            default: continue
            }
        }
        guard let pagesIn, let pagesOut else { return nil }
        self.init(pagesIn: pagesIn, pagesOut: pagesOut)
    }
}
