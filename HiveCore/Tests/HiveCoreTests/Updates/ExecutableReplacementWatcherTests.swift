import Foundation
@testable import HiveCore
import Synchronization
import Testing

struct ExecutableReplacementWatcherTests {
    private struct Stopped: Error {}

    private static let leaveAsIs: @Sendable () throws -> Void = {
        // The executable stays as it is until the next check.
    }

    private let temporary: TemporaryDirectory
    private let executable: URL

    init() throws {
        temporary = try TemporaryDirectory()
        executable = temporary.url.appending(path: "HiveDaemon")
        try Data("old daemon".utf8).write(to: executable)
    }

    /// Stands in for the time between checks: each pause runs the next step, and the watcher stops once they run out.
    private final class ScriptedPauses: Sendable {
        private let steps: Mutex<[@Sendable () throws -> Void]>
        let count = Mutex(0)

        init(_ steps: [@Sendable () throws -> Void]) {
            self.steps = Mutex(steps)
        }

        func pause() throws {
            let step = steps.withLock { $0.isEmpty ? nil : $0.removeFirst() }
            guard let step else { throw Stopped() }
            count.withLock { $0 += 1 }
            try step()
        }
    }

    private func watcher(_ pauses: ScriptedPauses) -> ExecutableReplacementWatcher {
        ExecutableReplacementWatcher(executable: executable, interval: .seconds(5)) { _ in try pauses.pause() }
    }

    /// Replaces the file the way an installer swaps in a new bundle: a new file moved over the old one.
    private func replace(with contents: String) throws {
        let staged = temporary.url.appending(path: "staged")
        try Data(contents.utf8).write(to: staged)
        _ = try FileManager.default.replaceItemAt(executable, withItemAt: staged)
    }

    @Test("Notices an executable replaced by a new file")
    func noticesReplacement() async throws {
        // Arrange
        let watcher = watcher(ScriptedPauses([{ try replace(with: "new daemon") }, Self.leaveAsIs]))

        // Act
        let isReplaced = await watcher.waitForReplacement()

        // Assert
        #expect(isReplaced)
    }

    @Test("Keeps Hive running while the executable stays the same")
    func keepsRunningWhenUnchanged() async {
        // Arrange
        let watcher = watcher(ScriptedPauses([Self.leaveAsIs, Self.leaveAsIs, Self.leaveAsIs]))

        // Act
        let isReplaced = await watcher.waitForReplacement()

        // Assert
        #expect(!isReplaced)
    }

    @Test("Waits while the new executable is missing or still being written")
    func waitsForASettledFile() async throws {
        // Arrange
        let executable = executable
        let pauses = ScriptedPauses([
            { try FileManager.default.removeItem(at: executable) },
            { try Data("new da".utf8).write(to: executable) },
            { try Data("new daemon".utf8).write(to: executable) },
            Self.leaveAsIs,
        ])
        let watcher = watcher(pauses)

        // Act
        let isReplaced = await watcher.waitForReplacement()

        // Assert
        #expect(isReplaced)
        #expect(pauses.count.withLock { $0 } == 4)
    }

    @Test("Can't watch an executable it can't read, and says so rather than restarting")
    func refusesMissingExecutable() async throws {
        // Arrange
        try FileManager.default.removeItem(at: executable)
        let watcher = watcher(ScriptedPauses([{ try replace(with: "new daemon") }, Self.leaveAsIs]))

        // Act
        let isReplaced = await watcher.waitForReplacement()

        // Assert
        #expect(!isReplaced)
    }
}
