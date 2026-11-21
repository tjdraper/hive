import ScoutProtocol

/// One disk's line of `/proc/diskstats`
/// (https://docs.kernel.org/admin-guide/iostats.html):
///
///     254 16 vdb 2606819 50967 510969893 54512 625125 454110 94497560 304833 0 642104 616548 ...
///
/// The device's numbers and name, then reads completed, merged, sectors read, milliseconds reading,
/// the same four for writes, requests in progress and milliseconds busy. A sector here is always 512
/// bytes, whatever the disk's own sector size.
struct DiskCounters: Equatable {
    var name: String
    var reads: UInt64
    var sectorsRead: UInt64
    var writes: UInt64
    var sectorsWritten: UInt64
    /// Kept by the kernel in 32 bits, so it wraps.
    var millisecondsBusy: UInt64

    init(name: String, reads: UInt64, sectorsRead: UInt64, writes: UInt64, sectorsWritten: UInt64, millisecondsBusy: UInt64) {
        self.name = name
        self.reads = reads
        self.sectorsRead = sectorsRead
        self.writes = writes
        self.sectorsWritten = sectorsWritten
        self.millisecondsBusy = millisecondsBusy
    }

    init?(parsing line: Substring) {
        let fields = line.split(byte: " ")
        guard fields.count >= 14 else { return nil }
        let numbers = fields[3...12].compactMap { UInt64($0) }
        guard numbers.count == 10 else { return nil }
        self.init(
            name: String(fields[2]),
            reads: numbers[0],
            sectorsRead: numbers[2],
            writes: numbers[4],
            sectorsWritten: numbers[6],
            millisecondsBusy: numbers[9]
        )
    }

    static func all(parsing text: String) -> [DiskCounters] {
        text.lines.compactMap(DiskCounters.init(parsing:))
    }

    /// Nil when a count went backwards, as when a disk is removed and another takes its name.
    func activity(since earlier: DiskCounters, seconds: Double) -> DiskActivity? {
        guard let reads = CounterIncrease.perSecond(earlier.reads, to: reads, seconds: seconds),
              let writes = CounterIncrease.perSecond(earlier.writes, to: writes, seconds: seconds),
              let sectorsRead = CounterIncrease.perSecond(earlier.sectorsRead, to: sectorsRead, seconds: seconds),
              let sectorsWritten = CounterIncrease.perSecond(earlier.sectorsWritten, to: sectorsWritten, seconds: seconds)
        else { return nil }
        let busySeconds = Double(CounterIncrease.of32Bit(earlier.millisecondsBusy, to: millisecondsBusy)) / 1000
        return DiskActivity(
            readBytesPerSecond: sectorsRead * 512,
            writtenBytesPerSecond: sectorsWritten * 512,
            readsPerSecond: reads,
            writesPerSecond: writes,
            busy: min(1, busySeconds / seconds)
        )
    }
}
