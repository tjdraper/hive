import Foundation
import HiveKit
import ScoutProtocol

/// What Hive will run for a `ScoutAction`, worked out from what the probe found and the Scout Hive.app
/// carries, before anything changes. The enrollment code, for the actions that need one, is added once
/// the plan holds, so a window is opened only for an action that will run.
struct ScoutActionPlan {
    enum Request {
        case install(CarriedScout.Release)
        case update(CarriedScout.Release)
        case enrollAgain
        case addresses([EnrollmentCode.Address])
        case uninstall
    }

    enum Made {
        case plan(ScoutActionPlan)
        case refused(ScoutActionProblem)
    }

    let command: String
    let request: Request

    var needsCode: Bool {
        switch request {
        case .install, .enrollAgain: true
        case .update, .addresses, .uninstall: false
        }
    }

    /// The request line, and the binary when there's one, with `code` for the actions that need one.
    func input(code: String?) throws -> Data {
        switch request {
        case .install(let release):
            try ScoutManagementCommand.input(.install(code: code), binary: release.binary)
        case .update(let release):
            try ScoutManagementCommand.input(
                .update(statement: release.statement, binaryLength: release.binary.count),
                binary: release.binary
            )
        case .enrollAgain:
            try ScoutManagementCommand.input(.install(code: code))
        case .addresses(let addresses):
            try ScoutManagementCommand.input(.addresses(addresses))
        case .uninstall:
            try ScoutManagementCommand.input(.uninstall)
        }
    }

    static func make(
        _ action: ScoutAction,
        check: ScoutServerCheck,
        carried: CarriedScout?,
        addresses: [EnrollmentCode.Address]
    ) -> Made {
        guard check.obstacle == nil, let platform = check.platform else { return .refused(.unsupported) }
        let release = carried?.release(for: platform)
        switch action {
        case .install:
            return installing(release, check: check)
        case .update:
            return managing(check) { installed in
                guard let release else { return .refused(.noCarriedRelease) }
                // Scout refuses one that isn't newer itself, but Hive never offers it one.
                guard installed < release.version else { return .refused(.upToDate) }
                return .request(.update(release))
            }
        case .enrollAgain:
            return managing(check) { _ in .request(.enrollAgain) }
        case .sendAddresses:
            return managing(check) { _ in addresses.isEmpty ? .refused(.noAddressOptions) : .request(.addresses(addresses)) }
        case .uninstall:
            return managing(check) { _ in .request(.uninstall) }
        }
    }

    /// For installing where there's no Scout, through the binary's own `manage`.
    private static func installing(_ release: CarriedScout.Release?, check: ScoutServerCheck) -> Made {
        guard check.access.canInstall else { return .refused(.noRootAccess) }
        guard !check.isInstalled else { return .refused(.alreadyInstalled) }
        guard let release, let command = ScoutManagementCommand.installCarried(sha256: release.sha256, through: check.access)
        else { return .refused(.noCarriedRelease) }
        return .plan(Self(command: command, request: .install(release)))
    }

    private enum RequestMade {
        case request(Request)
        case refused(ScoutActionProblem)
    }

    /// For the actions that go through the installed Scout's `manage`.
    private static func managing(
        _ check: ScoutServerCheck,
        request: (ScoutVersion) -> RequestMade
    ) -> Made {
        guard let command = ScoutManagementCommand.manage(through: check.access) else { return .refused(.noRootAccess) }
        guard let installed = check.installedVersion.flatMap(ScoutVersion.init(parsing:)) else { return .refused(.notInstalled) }
        switch request(installed) {
        case .request(let made): return .plan(Self(command: command, request: made))
        case .refused(let problem): return .refused(problem)
        }
    }
}
