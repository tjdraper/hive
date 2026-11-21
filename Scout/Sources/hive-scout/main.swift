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
}
