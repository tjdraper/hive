import Foundation
import ScoutCore

/// A server's files written by a test, for what no captured server shows, such as a counter that
/// wrapped or a server that restarted. Removed when the test ends.
final class TemporaryServer {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "scout-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var files: SystemFiles {
        SystemFiles(root: root.path(percentEncoded: false))
    }

    func write(_ path: String, _ text: String) throws {
        let file = root.appending(path: String(path.dropFirst()))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: root.appending(path: String(path.dropFirst())))
    }

    /// The time since the server started, and the ID that changes when it restarts.
    func writeClock(uptime: Double, bootID: String = "4d2a0b4e-0000-4000-8000-000000000001") throws {
        try write("/proc/uptime", "\(uptime) 0.00\n")
        try write("/proc/sys/kernel/random/boot_id", bootID + "\n")
    }

    /// A process's `stat` and `statm`, with the fields Scout doesn't read filled in plausibly.
    func writeProcess(
        pid: Int,
        command: String,
        cpuTicks: (user: UInt64, system: UInt64),
        startTicks: UInt64,
        pages: (resident: UInt64, shared: UInt64)
    ) throws {
        let stat = [
            "\(pid)", "(\(command))", "S", "1", "\(pid)", "\(pid)", "0", "-1", "4194560", "120", "0", "0", "0",
            "\(cpuTicks.user)", "\(cpuTicks.system)", "0", "0", "20", "0", "1", "0", "\(startTicks)", "8000000", "\(pages.resident)",
        ]
        try write("/proc/\(pid)/stat", stat.joined(separator: " ") + "\n")
        try write("/proc/\(pid)/statm", "2000 \(pages.resident) \(pages.shared) 10 0 300 0\n")
    }
}
