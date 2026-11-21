import ScoutProtocol

/// Reads each disk's activity, keeping the previous counters it's worked out from.
struct DiskReader {
    let files: SystemFiles
    private var previous: [String: DiskCounters] = [:]
    /// Which devices are disks, worked out again only when the kernel's list of devices changes.
    private var disks: (devices: [String], disks: Set<String>) = ([], [])

    init(files: SystemFiles) {
        self.files = files
    }

    /// - Parameter elapsed: seconds since the previous reading, nil when there's none to compare with.
    mutating func read(elapsed: Double?) -> [DiskFigures] {
        let devices = files.text(at: "/proc/diskstats").map(DiskCounters.all(parsing:)) ?? []
        let names = devices.map(\.name)
        if names != disks.devices {
            disks = (names, Self.disks(in: files))
        }
        let counters = devices.filter { disks.disks.contains($0.name) && ($0.reads > 0 || $0.writes > 0) }
        defer { previous = Dictionary(counters.map { ($0.name, $0) }) { first, _ in first } }
        return counters.map { disk in
            let activity = elapsed.flatMap { seconds in previous[disk.name].flatMap { disk.activity(since: $0, seconds: seconds) } }
            return DiskFigures(name: disk.name, activity: activity)
        }
    }

    /// `/sys/block` lists whole disks, never partitions. Those under `devices/virtual` are made by the
    /// kernel, such as loop devices, RAM disks, and LVM and RAID devices layered on the real disks,
    /// whose activity the disks underneath already count.
    static func disks(in files: SystemFiles) -> Set<String> {
        let names = files.entries(in: "/sys/block") ?? []
        return Set(names.filter { name in
            files.linkTarget(at: "/sys/block/\(name)").map { !$0.contains("/devices/virtual/") } ?? false
        })
    }
}
