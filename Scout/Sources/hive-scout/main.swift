#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import ScoutCore
import ScoutProtocol

guard let command = ScoutCommand(arguments: Array(CommandLine.arguments.dropFirst())) else {
    Console.log(ScoutCommand.usage)
    exit(64)
}

switch command {
case .sample:
    let sample = try await ScoutEventLoop.shared.run {
        var sampler = Sampler()
        return await sampler.sample(takenAt: SampleSchedule.now() / 1_000_000_000)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    Console.print(try encoder.encode(sample))
case .watch(let target):
    do {
        try await ScoutEventLoop.shared.run { try await WatchLoop(target: target).run() }
    } catch HiveConnectionError.keyNotPinned {
        exit(1)
    } catch {
        Console.log("Stopped: \(error)")
        exit(1)
    }
case .enroll(let stateDirectory):
    guard let code = CodeInput.read() else {
        Console.log("That isn't a whole enrollment code. Copy it again from Beekeeper.")
        exit(65)
    }
    do {
        let store = EnrollmentStore(directory: stateDirectory)
        let enrollment = try await ScoutEventLoop.shared.run {
            try await EnrollmentWorkflow(connector: PinnedHiveConnector(), store: store).enroll(with: code)
        }
        Console.log("Enrolled with the Hive for server \(enrollment.serverID), and signed in")
    } catch {
        Console.log(EnrollmentMessage.text(for: error))
        exit(1)
    }
case let .run(stateDirectory, runtimeDirectory):
    let enrollment: SavedEnrollment
    do {
        guard let saved = try EnrollmentStore(directory: stateDirectory).load() else {
            Console.log("This server's Scout hasn't enrolled. Run hive-scout enroll with a code from Beekeeper first.")
            exit(78)
        }
        enrollment = saved
    } catch {
        Console.log("Couldn't read the enrollment in the state folder: \(error)")
        exit(78)
    }
    do {
        let loop = RunLoop(enrollment: enrollment, statusFile: SendingStatusFile(directory: runtimeDirectory))
        try await ScoutEventLoop.shared.run { try await loop.run() }
    } catch {
        Console.log("Stopped: \(error)")
        exit(1)
    }
case .status(let runtimeDirectory):
    do {
        let status = try SendingStatusFile(directory: runtimeDirectory).load()
        Console.log(StatusReport.text(for: status, now: SampleSchedule.now() / 1_000_000_000))
    } catch {
        Console.log("Couldn't read the running Scout's status: \(error)")
        exit(1)
    }
}
