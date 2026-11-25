#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Keeps each process's `stat` and `statm` open between readings and reads them again from the start,
/// which the kernel answers with fresh figures. Opening and closing two files for each of hundreds of
/// processes was most of the CPU time Scout spent, nearly all of it in the kernel finding the files.
///
/// A file stays tied to the process it was opened for: once that process exits, reading it fails, and
/// the files are opened again by path, which finds a new process given the same ID.
///
/// The user a process runs as is read when its files are opened, from who owns them. A process that
/// runs another program, as one does to become another user through a setuid program such as `sudo`,
/// has a new command name, so its files are opened again and its user read afresh.
final class OpenProcessFiles {
    private struct Files {
        var stat: Int32
        /// Nil for a kernel thread, which has no memory of its own.
        var statm: Int32?
        var userID: UInt32
        var command: String
    }

    struct Reading {
        var stat: ProcessFiles.Stat
        var userID: UInt32
        var ownPages: UInt64
    }

    let files: SystemFiles
    private let limit: Int
    private var held: [Int32: Files] = [:]
    /// Reused for every file.
    private var buffer = [UInt8](repeating: 0, count: 4096)

    /// - Parameter limit: how many processes' files to keep open. The rest are opened for each reading.
    init(files: SystemFiles, limit: Int = OpenProcessFiles.limit()) {
        self.files = files
        self.limit = limit
    }

    deinit {
        for files in held.values {
            close(files)
        }
    }

    /// The process's figures, or nil when it has exited, even between being listed and being read.
    func read(pid: Int32) -> Reading? {
        if let files = held[pid] {
            if let reading = read(files), reading.stat.command == files.command { return reading }
            close(files)
            held[pid] = nil
        }
        guard let opened = openFiles(of: pid), let reading = read(opened) else { return nil }
        if held.count < limit {
            held[pid] = opened
        } else {
            close(opened)
        }
        return reading
    }

    /// Closes the files of processes that weren't listed this reading.
    func closeAll(except listed: Set<Int32>) {
        for (pid, files) in held where !listed.contains(pid) {
            close(files)
            held[pid] = nil
        }
    }

    private func read(_ files: Files) -> Reading? {
        guard let stat = readAgain(files.stat).flatMap(ProcessFiles.stat(parsing:)) else { return nil }
        var ownPages: UInt64 = 0
        if let statm = files.statm {
            guard let pages = readAgain(statm).flatMap(ProcessFiles.ownMemoryPages(parsing:)) else { return nil }
            ownPages = pages
        }
        return Reading(stat: stat, userID: files.userID, ownPages: ownPages)
    }

    private func openFiles(of pid: Int32) -> Files? {
        guard let (stat, userID) = files.openFile("/proc/\(pid)/stat") else { return nil }
        // Whether it's a kernel thread, with no statm worth opening, is in its stat.
        guard let parsed = readAgain(stat).flatMap(ProcessFiles.stat(parsing:)) else {
            SystemFiles.close(stat)
            return nil
        }
        if parsed.isKernelThread { return Files(stat: stat, statm: nil, userID: userID, command: parsed.command) }
        guard let (statm, _) = files.openFile("/proc/\(pid)/statm") else {
            SystemFiles.close(stat)
            return nil
        }
        return Files(stat: stat, statm: statm, userID: userID, command: parsed.command)
    }

    private func readAgain(_ descriptor: Int32) -> ArraySlice<UInt8>? {
        SystemFiles.readFromStart(descriptor, into: &buffer, inOneRead: true).map { buffer[..<$0] }
    }

    private func close(_ files: Files) {
        SystemFiles.close(files.stat)
        if let statm = files.statm { SystemFiles.close(statm) }
    }

    /// Two files for each process, up to a thousand processes, within the limit on open files raised
    /// as far as it goes, keeping room for Scout's connections and the cgroups' files.
    static func limit() -> Int {
        #if canImport(Glibc)
        let openFiles = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
        #else
        let openFiles = RLIMIT_NOFILE
        #endif
        var limit = rlimit()
        guard getrlimit(openFiles, &limit) == 0 else { return 0 }
        if limit.rlim_cur < limit.rlim_max {
            limit.rlim_cur = limit.rlim_max
            _ = setrlimit(openFiles, &limit)
            _ = getrlimit(openFiles, &limit)
        }
        let available = Int(clamping: limit.rlim_cur) - 64 - CgroupReader.heldUnitLimit * CgroupReader.filesPerUnit
        return max(0, min(1000, available / 2))
    }
}
