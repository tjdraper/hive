import Darwin
import Foundation
import os

/// An update replaces Hive.app while the daemon runs, through Sparkle or an installer package, and
/// launchd keeps running the old executable until the daemon exits. So the daemon watches its own
/// executable and restarts once it's been replaced, and launchd's `KeepAlive` starts the new one.
struct ExecutableReplacementWatcher: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Updates")

    struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int

        init?(path: String) {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
        }
    }

    let executable: URL
    let interval: Duration
    let pause: @Sendable (Duration) async throws -> Void

    init(
        executable: URL,
        interval: Duration = .seconds(5),
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.executable = executable
        self.interval = interval
        self.pause = pause
    }

    /// Returns true once the executable has been replaced, or false when cancelled or when it can't be
    /// watched. A changed file has to look the same on two checks in a row, so an installer still
    /// writing it isn't started half written.
    func waitForReplacement() async -> Bool {
        let path = executable.fileSystemPath
        guard let original = FileIdentity(path: path) else {
            Self.logger.error("Can't read Hive's executable, so an update won't restart Hive")
            return false
        }
        var previous = original
        while true {
            do {
                try await pause(interval)
            } catch {
                return false
            }
            // Missing for a moment while an installer swaps the bundle.
            guard let current = FileIdentity(path: path) else { continue }
            if current != original, current == previous {
                return true
            }
            previous = current
        }
    }
}
