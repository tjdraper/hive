#if os(macOS)
import Darwin
import ScoutCore

/// `run` on a Mac, started as root by launchd. Only root can read other users' processes, so it keeps
/// root only to take samples, and hands each to the `send` it starts, which drops to Scout's user
/// before anything else and does the rest: the key, the connection to Hive, and what's held. Root
/// reads nothing back from it, nor anything from the network or Scout's state folder.
enum PrivilegedSampling {
    static func run(stateDirectory: String, runtimeDirectory: String) async throws {
        let sender = try SampleHandover.start([
            ScoutRelease.executablePath, "send", "--state-directory", stateDirectory, "--runtime-directory", runtimeDirectory,
        ])
        let reloads = try await ReloadSignal.listen(on: .shared)
        let passingOn = Task(executorPreference: ScoutEventLoop.shared) {
            for await _ in reloads { sender.passOn(signal: SIGHUP) }
        }
        defer { passingOn.cancel() }
        var sampler = MacSampler()
        while true {
            let mark = SampleSchedule.nextMark(after: SampleSchedule.now())
            try await ScoutEventLoop.shared.sleep(untilWallClock: mark)
            // Fails once `send` has stopped, which ends this too, so launchd starts both again.
            try sender.hand(await sampler.sample(takenAt: mark / 1_000_000_000))
        }
    }
}
#endif
