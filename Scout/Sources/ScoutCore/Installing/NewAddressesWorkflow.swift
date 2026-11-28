#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import ScoutProtocol

public enum NewAddressesError: Error, Equatable {
    case notRoot
    case notInstalled
    case notAddresses
    /// The Scout said why itself, or couldn't start.
    case notSaved
    case reloadFailed(command: String, output: String)
}

/// `hive-scout manage`'s addresses, run as root: gives the enrolled Scout the Hive's new addresses
/// and has the running service read them, so it needn't enroll again. Saving runs as a program of
/// its own that drops to Scout's user, since root never touches the state folder. The pin stays the
/// one Scout enrolled with, so new addresses can only lead to the same Hive.
public struct NewAddressesWorkflow {
    let layout: InstallLayout
    let system: any ServerSystem
    /// The binary to save with, as this machine sees it.
    let source: String

    public init() {
        self.init(layout: .server, system: PosixServerSystem(), source: ScoutRelease.executablePath)
    }

    init(layout: InstallLayout, system: any ServerSystem, source: String) {
        self.layout = layout
        self.system = system
        self.source = source
    }

    public func replace(with addresses: [EnrollmentCode.Address]) throws(NewAddressesError) {
        guard system.isRoot else { throw .notRoot }
        let tools = ServerTools(layout: layout)
        guard system.user(named: layout.user) != nil,
              let initSystem = InitSystem.running(in: layout, tools: tools),
              access(layout.onDisk(initSystem.servicePath(in: layout)), F_OK) == 0
        else { throw .notInstalled }
        guard ManagementRequest.areAddresses(addresses), let json = try? JSONEncoder().encode(addresses) else {
            throw .notAddresses
        }
        guard system.replaceAddresses(json: Array(json), binary: source, stateDirectory: layout.stateDirectory) else {
            throw .notSaved
        }

        let name = layout.user
        let reload = switch initSystem {
        case .systemd: [tools.find("systemctl") ?? "systemctl", "reload", name]
        case .openRC: [tools.find("rc-service") ?? "rc-service", name, "reload"]
        case .launchd: [tools.find("launchctl") ?? "launchctl", "kill", "SIGHUP", InitSystem.launchdTarget]
        }
        let result = system.run(reload)
        guard result.status == 0 else { throw .reloadFailed(command: reload.joined(separator: " "), output: result.output) }
    }
}
