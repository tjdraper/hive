import Foundation
import os
import Synchronization

/// Stops Hive gracefully so launchd starts it again, which its `KeepAlive` does, such as to take up a
/// new identity key. A run going now is cut short and picked up after the restart, as with any stop.
final class HiveRestart: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "DaemonStartup")

    /// Long enough for the response to the request that asked for it to reach the device.
    let delay: Duration
    private let requested = Mutex(false)
    private let stream: AsyncStream<Void>
    private let input: AsyncStream<Void>.Continuation

    init(delay: Duration) {
        self.delay = delay
        (stream, input) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    var isRequested: Bool {
        requested.withLock { $0 }
    }

    /// After `delay`.
    func request() {
        requested.withLock { $0 = true }
        Self.logger.notice("Restarting Hive")
        Task { [delay, input] in
            try? await Task.sleep(for: delay)
            input.yield()
        }
    }

    /// Returns once a restart is due, or the task is cancelled.
    func wait() async {
        for await _ in stream {
            return
        }
    }
}
