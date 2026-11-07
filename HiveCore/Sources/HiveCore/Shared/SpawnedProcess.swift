import Darwin
import Foundation
import Synchronization

enum SpawnedProcessError: Error, Equatable {
    case couldNotStart(errno: Int32)
}

/// A child process in Hive's own process group. When a launchd job exits, launchd kills whatever is
/// left in its process group, so a child can never outlive Hive, even when Hive crashes. Foundation's
/// `Process` gives each child a group of its own, which launchd leaves running: an rsync left that
/// way kept writing into the partial snapshot the next run picked up.
final class SpawnedProcess: Sendable {
    let processIdentifier: pid_t
    /// The exit status once it has ended, or the signal that ended it, as `Process.terminationStatus` gives.
    private let status = Mutex<Int32?>(nil)

    /// The child gets `standardInput`, `standardOutput` and `standardError` as its descriptors 0, 1 and 2,
    /// and no other descriptor of Hive's. `exited` gets its status once it has ended.
    init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Int32,
        standardOutput: Int32,
        standardError: Int32,
        exited: @escaping @Sendable (Int32) -> Void
    ) throws {
        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, standardInput, 0)
        posix_spawn_file_actions_adddup2(&actions, standardOutput, 1)
        posix_spawn_file_actions_adddup2(&actions, standardError, 2)

        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // The daemon ignores SIGPIPE and may block signals, which a child would otherwise inherit.
        var everySignal = sigset_t()
        sigfillset(&everySignal)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        let path = executable.fileSystemPath
        let argv = Self.cStrings([path] + arguments)
        let envp = Self.cStrings(environment.map { "\($0.key)=\($0.value)" })
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var spawned: pid_t = 0
        let result = posix_spawn(&spawned, path, &actions, &attributes, argv + [nil], envp + [nil])
        guard result == 0 else { throw SpawnedProcessError.couldNotStart(errno: result) }
        let processIdentifier = spawned
        self.processIdentifier = processIdentifier

        // A thread of its own blocked waiting can't miss an exit that happens before anything is
        // listening for it, which watching for the exit could. It waits without reaping, and reaps
        // only under the lock, so `signal` can never reach another process given the same number.
        Thread.detachNewThread { [self] in
            var info = siginfo_t()
            while waitid(P_PID, id_t(processIdentifier), &info, WEXITED | WNOWAIT) == -1, errno == EINTR { continue }
            let ended = self.status.withLock { status in
                var raw: Int32 = 0
                while waitpid(processIdentifier, &raw, 0) == -1, errno == EINTR { continue }
                let ended = Self.status(fromWait: raw)
                status = ended
                return ended
            }
            exited(ended)
        }
    }

    var isRunning: Bool {
        status.withLock { $0 == nil }
    }

    func signal(_ signal: Int32) {
        // Once it has been reaped its number can belong to another process.
        status.withLock { if $0 == nil { kill(processIdentifier, signal) } }
    }

    /// The exit code, or the signal that ended it.
    private static func status(fromWait raw: Int32) -> Int32 {
        let signal = raw & 0x7F
        return signal == 0 ? (raw >> 8) & 0xFF : signal
    }

    private static func cStrings(_ strings: [String]) -> [UnsafeMutablePointer<CChar>?] {
        strings.map { strdup($0) }
    }
}
