#if os(macOS)
import Foundation
import IOKit
import ScoutProtocol

/// One disk's counters from IOKit, kept by its `IOBlockStorageDriver` in a dictionary named Statistics,
/// as `iostat` reads them.
struct MacDiskCounters: Equatable {
    var name: String
    var readBytes: UInt64
    var writtenBytes: UInt64
    var reads: UInt64
    var writes: UInt64

    init(name: String, readBytes: UInt64, writtenBytes: UInt64, reads: UInt64, writes: UInt64) {
        self.name = name
        self.readBytes = readBytes
        self.writtenBytes = writtenBytes
        self.reads = reads
        self.writes = writes
    }

    init?(name: String, statistics: [String: Any]) {
        let value = { (key: String) in (statistics[key] as? NSNumber)?.uint64Value }
        guard let readBytes = value("Bytes (Read)"), let writtenBytes = value("Bytes (Write)"),
              let reads = value("Operations (Read)"), let writes = value("Operations (Write)")
        else { return nil }
        self.init(name: name, readBytes: readBytes, writtenBytes: writtenBytes, reads: reads, writes: writes)
    }

    /// Nil when a counter went backwards, as when a disk is ejected and another takes its name. A Mac
    /// counts how long requests took, which overlap, rather than how long the disk was busy, so busy
    /// is left out.
    func activity(since earlier: MacDiskCounters, seconds: Double) -> DiskActivity? {
        let rate = { (keyPath: KeyPath<MacDiskCounters, UInt64>) in
            CounterIncrease.perSecond(earlier[keyPath: keyPath], to: self[keyPath: keyPath], seconds: seconds)
        }
        guard let readBytes = rate(\.readBytes), let writtenBytes = rate(\.writtenBytes), let reads = rate(\.reads),
              let writes = rate(\.writes)
        else { return nil }
        return DiskActivity(
            readBytesPerSecond: readBytes,
            writtenBytesPerSecond: writtenBytes,
            readsPerSecond: reads,
            writesPerSecond: writes,
            busy: nil
        )
    }

    /// A disk image's activity is the disk it's on's too, so it's left out, as Linux's loop devices are.
    /// IOKit says what connects each disk, such as Apple Fabric for the internal one, or USB.
    static func isPhysical(interconnect: String?) -> Bool {
        interconnect != "Virtual Interface"
    }

    /// Every physical disk's, by its BSD name, such as `disk0`.
    static func all() -> [MacDiskCounters] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var disks: [MacDiskCounters] = []
        while case let driver = IOIteratorNext(iterator), driver != 0 {
            defer { IOObjectRelease(driver) }
            guard isPhysical(interconnect: interconnect(of: driver)), let name = mediaName(of: driver),
                  let statistics = property("Statistics", of: driver) as? [String: Any],
                  let counters = MacDiskCounters(name: name, statistics: statistics)
            else { continue }
            disks.append(counters)
        }
        return disks
    }

    private static func interconnect(of driver: io_registry_entry_t) -> String? {
        var device: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &device) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(device) }
        let characteristics = property("Protocol Characteristics", of: device) as? [String: Any]
        return characteristics?["Physical Interconnect"] as? String
    }

    /// The whole disk's media, the driver's one child.
    private static func mediaName(of driver: io_registry_entry_t) -> String? {
        var media: io_registry_entry_t = 0
        guard IORegistryEntryGetChildEntry(driver, kIOServicePlane, &media) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(media) }
        return property("BSD Name", of: media) as? String
    }

    private static func property(_ name: String, of entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// Reads each of a Mac's disks' activity, keeping the previous counters it's worked out from.
struct MacDiskReader {
    private var previous: [String: MacDiskCounters] = [:]

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> [DiskFigures] {
        let counters = MacDiskCounters.all().filter { $0.reads > 0 || $0.writes > 0 }.sorted { $0.name < $1.name }
        defer { previous = Dictionary(counters.map { ($0.name, $0) }) { first, _ in first } }
        return counters.map { disk in
            let activity = elapsed.flatMap { seconds in previous[disk.name].flatMap { disk.activity(since: $0, seconds: seconds) } }
            return DiskFigures(name: disk.name, activity: activity)
        }
    }
}
#endif
