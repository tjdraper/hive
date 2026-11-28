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

#if os(macOS)
// On a Mac, `run` started as root keeps root only to take samples, and its `send` drops it.
let dropsRootFirst = command.dropsRootFirst && !(command.isRun && geteuid() == 0)
#else
let dropsRootFirst = command.dropsRootFirst
#endif
if dropsRootFirst {
    do {
        try ScoutUser.dropRoot()
    } catch {
        Console.log(ScoutUser.message(for: error))
        exit(77)
    }
}

switch command {
case .sample:
    let sample = try await ScoutEventLoop.shared.run {
        var sampler = ServerSampler()
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
    guard case .code(let code) = CodeInput.read(prompt: "Paste the enrollment code from Beekeeper, then press Return:") else {
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
case .addresses(let stateDirectory):
    guard let bytes = ManagementInput.readAll(from: STDIN_FILENO, limit: ManagementRequest.longestLine),
          let addresses = try? JSONDecoder().decode([EnrollmentCode.Address].self, from: Data(bytes)),
          ManagementRequest.areAddresses(addresses)
    else {
        Console.log("Those aren't addresses Scout can use. Nothing was changed.")
        exit(65)
    }
    do throws(AddressChangeError) {
        try EnrollmentStore(directory: stateDirectory).replaceAddresses(with: addresses)
        Console.log("Saved \(addresses.count) addresses for the Hive.")
    } catch .notEnrolled {
        Console.log("This server's Scout hasn't enrolled, so it has no addresses to replace.")
        exit(78)
    } catch {
        Console.log("Couldn't save the addresses: \(error)")
        exit(1)
    }
case let .run(stateDirectory, runtimeDirectory) where !dropsRootFirst:
    #if os(macOS)
    do {
        try await ScoutEventLoop.shared.run {
            try await PrivilegedSampling.run(stateDirectory: stateDirectory, runtimeDirectory: runtimeDirectory)
        }
    } catch {
        Console.log("Stopped: \(error)")
        exit(1)
    }
    #endif
case let .run(stateDirectory, runtimeDirectory), let .send(stateDirectory, runtimeDirectory):
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
        try await ScoutEventLoop.shared.run {
            let samples = if case .send = command {
                try await SampleHandover.samples(on: .shared)
            } else {
                RunLoop.samplesTakenHere()
            }
            let loop = RunLoop(
                enrollment: enrollment,
                store: EnrollmentStore(directory: stateDirectory),
                statusFile: SendingStatusFile(directory: runtimeDirectory),
                samples: samples
            )
            try await loop.run()
        }
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
case .install(let sshUser):
    do {
        try InstallWorkflow { Console.log($0) }.install(sshUser: sshUser) { () throws(InstallError) in
            let prompt = "Paste the enrollment code from Beekeeper, then press Return. "
                + "To keep this server's enrollment, press Return alone:"
            switch CodeInput.read(prompt: prompt) {
            case .code(let code): return code
            case .nothing: return nil
            case .notACode: throw .notACode
            }
        }
    } catch {
        Console.log(InstallMessage.text(for: error))
        exit(1)
    }
case .uninstall:
    do {
        try UninstallWorkflow { Console.log($0) }.uninstall()
    } catch {
        Console.log(InstallMessage.text(for: error))
        exit(1)
    }
case .manage:
    let response = ManageCommand.respond(to: ManagementInput.read())
    Console.print(try JSONEncoder().encode(response))
    exit(response.outcome == .done ? 0 : 1)
}
