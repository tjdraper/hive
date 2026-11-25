#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import ScoutProtocol

/// Reads every process, groups them by command, user and the container or service they're in, and
/// keeps each one's CPU time to work out its share at the next reading.
struct ProcessReader {
    struct Reading {
        var figures: ProcessFigures
        /// Each container's command names, the one using the most memory first.
        var containerCommands: [String: [String]]
    }

    private struct ProcessID: Hashable {
        var pid: Int32
        var startTicks: UInt64
    }

    private struct GroupKey: Hashable {
        var command: String
        var userID: UInt32
        var unit: CgroupUnit?
    }

    static let groupsByEachMeasure = 10
    static let commandsByContainer = 3

    let files: SystemFiles
    private let pageSize: UInt64
    private let clockTicksPerSecond: Double
    private var users: UserNames
    private var previousCPUTicks: [ProcessID: UInt64] = [:]
    private let processFiles: OpenProcessFiles

    init(
        files: SystemFiles,
        pageSize: UInt64 = UInt64(sysconf(Int32(_SC_PAGESIZE))),
        clockTicksPerSecond: Double = Double(sysconf(Int32(_SC_CLK_TCK))),
        openFileLimit: Int = OpenProcessFiles.limit()
    ) {
        self.files = files
        self.pageSize = pageSize
        self.clockTicksPerSecond = clockTicksPerSecond
        users = UserNames(files: files)
        processFiles = OpenProcessFiles(files: files, limit: openFileLimit)
    }

    /// - Parameters:
    ///   - time: when this reading is taken.
    ///   - elapsed: seconds since the previous reading, nil when there's none to compare with.
    ///   - units: the container or service each process is in.
    mutating func read(at time: ReadingTime?, elapsed: Double?, units: [Int32: CgroupUnit] = [:]) -> Reading? {
        guard let entries = files.entries(in: "/proc") else { return nil }
        users.refresh()

        // Clock ticks since the server started, at the previous reading.
        var previousReadingTicks: UInt64?
        if let time, let elapsed {
            previousReadingTicks = UInt64(max(0, time.uptimeSeconds - elapsed) * clockTicksPerSecond)
        }
        var cpuTicks: [ProcessID: UInt64] = [:]
        cpuTicks.reserveCapacity(previousCPUTicks.count)
        var groups: [GroupKey: ProcessGroup] = [:]
        var count = 0
        var zombies = 0
        var listed: Set<Int32> = []

        for entry in entries {
            guard let pid = Int32(entry) else { continue }
            listed.insert(pid)
            // A process that exits between listing and reading is skipped.
            guard let reading = processFiles.read(pid: pid) else { continue }
            let (stat, userID, ownPages) = (reading.stat, reading.userID, reading.ownPages)
            count += 1
            if stat.state == UInt8(ascii: "Z") { zombies += 1 }

            let id = ProcessID(pid: pid, startTicks: stat.startTicks)
            cpuTicks[id] = stat.cpuTicks
            let key = GroupKey(command: stat.command, userID: userID, unit: units[pid])
            var group = groups[key]
                ?? ProcessGroup(command: stat.command, user: "", count: 0, cpuCores: elapsed.map { _ in 0 }, ownMemoryBytes: 0)
            group.count += 1
            group.ownMemoryBytes += ownPages * pageSize
            if let previousReadingTicks, let elapsed {
                // A process that started since the previous reading did all its work in between, so
                // all of it counts. That includes one given the ID of a process that has exited.
                let earlierTicks = previousCPUTicks[id] ?? (stat.startTicks >= previousReadingTicks ? 0 : stat.cpuTicks)
                group.cpuCores? += Double(CounterIncrease.of(earlierTicks, to: stat.cpuTicks) ?? 0) / clockTicksPerSecond / elapsed
            }
            groups[key] = group
        }
        previousCPUTicks = cpuTicks
        processFiles.closeAll(except: listed)

        let top = Self.top(of: groups)
        let figures = ProcessFigures(
            count: count,
            zombies: zombies,
            groups: top.map { key, group in
                var group = group
                // A container's users are another system's, which the server's names would misname.
                group.user = key.unit?.kind == .container ? String(key.userID) : users.name(of: key.userID)
                group.containerID = key.unit?.kind == .container ? key.unit?.name : nil
                group.service = key.unit?.kind == .service ? key.unit?.name : nil
                return group
            }
        )
        return Reading(figures: figures, containerCommands: Self.containerCommands(of: groups))
    }

    private static func containerCommands(of groups: [GroupKey: ProcessGroup]) -> [String: [String]] {
        var memory: [String: [String: UInt64]] = [:]
        for (key, group) in groups {
            guard let unit = key.unit, unit.kind == .container else { continue }
            memory[unit.name, default: [:]][key.command, default: 0] += group.ownMemoryBytes
        }
        return memory.mapValues { byCommand in
            byCommand.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(commandsByContainer).map(\.key)
        }
    }

    /// The top groups by CPU and by memory, each group once, busiest first.
    private static func top(of groups: [GroupKey: ProcessGroup]) -> [(key: GroupKey, value: ProcessGroup)] {
        let all = Array(groups)
        let byCPU = all.sorted { ($0.value.cpuCores ?? 0, $0.value.ownMemoryBytes) > ($1.value.cpuCores ?? 0, $1.value.ownMemoryBytes) }
        let byMemory = all.sorted { $0.value.ownMemoryBytes > $1.value.ownMemoryBytes }
        var chosen: Set<GroupKey> = []
        var top: [(key: GroupKey, value: ProcessGroup)] = []
        for group in byCPU.prefix(groupsByEachMeasure) + byMemory.prefix(groupsByEachMeasure) where chosen.insert(group.key).inserted {
            top.append(group)
        }
        return top
    }
}
