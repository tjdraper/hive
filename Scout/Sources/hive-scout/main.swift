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
    var sampler = Sampler()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let sample = sampler.sample(takenAt: SampleSchedule.now() / 1_000_000_000)
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
