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
}
