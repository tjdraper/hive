#if os(macOS)
import Darwin
import ScoutProtocol

/// One process on a Mac. Every process's user and state can be read, but only root can read another
/// user's CPU time, memory or name, so `usage` is nil for those.
struct MacProcess: Equatable {
    struct Usage: Equatable {
        /// `mach_absolute_time` when it started, which tells it from a process given its ID later.
        var startTime: UInt64
        var cpuNanoseconds: UInt64
        /// What Activity Monitor shows as its memory: what it has resident or compressed of its own,
        /// leaving out what it shares, such as libraries.
        var footprintBytes: UInt64
    }

    var pid: Int32
    var userID: UInt32
    var command: String
    var isZombie: Bool
    var usage: Usage?
}

/// Reads every process on a Mac, groups the readable ones by command and user, as on Linux, and
/// keeps each one's CPU time to work out its share at the next reading.
struct MacProcessReader {
    struct ProcessID: Hashable {
        var pid: Int32
        var startTime: UInt64
    }

    /// The previous reading, that CPU shares are worked out from.
    struct Previous {
        var cpu: [ProcessID: UInt64]
        /// `mach_absolute_time` when it was taken.
        var readAt: UInt64
    }

    struct GroupKey: Hashable {
        var command: String
        var userID: UInt32
    }

    /// A name is read again when the short name changes, as it does when a process runs another program.
    struct NameKey: Hashable {
        var id: ProcessID
        var shortName: String
    }

    private var previousCPU: [ProcessID: UInt64] = [:]
    private var previousReadAt: UInt64?
    private var names: [NameKey: String] = [:]
    private var users: [UInt32: String] = [:]
    private let timebase: (numerator: UInt64, denominator: UInt64)

    init() {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        timebase = (UInt64(info.numer), UInt64(info.denom))
    }

    /// - Parameter busyCores: cores' worth of CPU every core together was busy since the previous
    ///   reading, which what other users' processes used is worked out from.
    mutating func read(elapsed: Double?, busyCores: Double?) -> ProcessFigures? {
        let readAt = mach_absolute_time()
        let (processes, names) = Self.all(timebase: timebase, knownNames: names)
        guard !processes.isEmpty else { return nil }
        defer {
            self.names = names
            previousCPU = Dictionary(processes.compactMap { process in
                process.usage.map { (ProcessID(pid: process.pid, startTime: $0.startTime), $0.cpuNanoseconds) }
            }) { first, _ in first }
            previousReadAt = readAt
        }
        for userID in Set(processes.map(\.userID)) where users[userID] == nil {
            users[userID] = Self.userName(of: userID)
        }
        return Self.figures(
            of: processes,
            previous: elapsed == nil ? nil : previousReadAt.map { Previous(cpu: previousCPU, readAt: $0) },
            elapsed: elapsed,
            busyCores: busyCores,
            users: users
        )
    }

    /// - Parameter previous: nil when there's no reading to compare with.
    static func figures(
        of processes: [MacProcess],
        previous: Previous?,
        elapsed: Double?,
        busyCores: Double?,
        users: [UInt32: String]
    ) -> ProcessFigures {
        var groups: [GroupKey: ProcessGroup] = [:]
        var readable = 0
        var ownCores = 0.0
        for process in processes {
            guard let usage = process.usage else { continue }
            readable += 1
            let key = GroupKey(command: process.command, userID: process.userID)
            var group = groups[key]
                ?? ProcessGroup(command: process.command, user: "", count: 0, cpuCores: elapsed.map { _ in 0 }, ownMemoryBytes: 0)
            group.count += 1
            group.ownMemoryBytes += usage.footprintBytes
            if let previous, let elapsed {
                // As on Linux, one that started since the previous reading did all its work in between.
                let id = ProcessID(pid: process.pid, startTime: usage.startTime)
                let earlier = previous.cpu[id] ?? (usage.startTime >= previous.readAt ? 0 : usage.cpuNanoseconds)
                let cores = Double(CounterIncrease.of(earlier, to: usage.cpuNanoseconds) ?? 0) / 1_000_000_000 / elapsed
                group.cpuCores? += cores
                ownCores += cores
            }
            groups[key] = group
        }

        let otherUsers = readable < processes.count ? OtherUsersProcesses(
            count: processes.count - readable,
            cpuCores: previous == nil ? nil : busyCores.map { max(0, $0 - ownCores) }
        ) : nil
        return ProcessFigures(
            count: processes.count,
            zombies: processes.count(where: \.isZombie),
            groups: ProcessReader.top(of: groups).map { key, group in
                var group = group
                group.user = users[key.userID] ?? String(key.userID)
                return group
            },
            otherUsers: otherUsers
        )
    }

    /// Every process, with the long names of those that can be read, by process and short name.
    /// Each is a few calls into the kernel for each of hundreds of processes, the most a sample costs,
    /// so names already known aren't read again, nor anything of another user's but its user and state
    /// without root, since macOS refuses it.
    private static func all(
        timebase: (numerator: UInt64, denominator: UInt64),
        knownNames: [NameKey: String]
    ) -> (processes: [MacProcess], names: [NameKey: String]) {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return ([], [:]) }
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size)))
        guard count > 0 else { return ([], [:]) }
        let user = geteuid()
        var names: [NameKey: String] = [:]
        let processes = pids.prefix(min(count, capacity)).compactMap { pid -> MacProcess? in
            // One that exits between listing and reading is skipped.
            var info = proc_bsdshortinfo()
            let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
            let shortName = MacMount.string(&info.pbsi_comm)
            let usage = user == 0 || info.pbsi_uid == user ? Self.usage(of: pid, timebase: timebase) : nil
            var command = shortName
            if let usage {
                let key = NameKey(id: ProcessID(pid: pid, startTime: usage.startTime), shortName: shortName)
                command = knownNames[key] ?? Self.name(of: pid) ?? shortName
                names[key] = command
            }
            return MacProcess(
                pid: pid,
                userID: info.pbsi_uid,
                command: command,
                isZombie: info.pbsi_status == UInt32(SZOMB),
                usage: usage
            )
        }
        return (processes, names)
    }

    /// Its CPU times are in `mach_absolute_time`'s units, which are nanoseconds on an Intel Mac but
    /// not on Apple silicon.
    private static func usage(of pid: Int32, timebase: (numerator: UInt64, denominator: UInt64)) -> MacProcess.Usage? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return nil }
        let ticks = info.ri_user_time + info.ri_system_time
        return MacProcess.Usage(
            startTime: info.ri_proc_start_abstime,
            cpuNanoseconds: timebase.denominator.dividingFullWidth(ticks.multipliedFullWidth(by: timebase.numerator)).quotient,
            footprintBytes: info.ri_phys_footprint
        )
    }

    /// The longer name Activity Monitor shows, rather than the first 16 characters.
    private static func name(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        // swiftlint:disable:next optional_data_string_conversion
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    private static func userName(of userID: UInt32) -> String {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)
        guard getpwuid_r(userID, &entry, &buffer, buffer.count, &result) == 0, result != nil, let name = entry.pw_name else {
            return String(userID)
        }
        return String(cString: name)
    }
}
#endif
