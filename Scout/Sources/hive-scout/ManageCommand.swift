import ScoutCore
import ScoutProtocol

/// `hive-scout manage`: carries out the request Hive sent and says how it went. Run as root, it never
/// reads Scout's state folder; enrolling drops to Scout's user in a program of its own, as `install` does.
enum ManageCommand {
    static func respond(to input: ManagementInput?) -> ManagementResponse {
        guard let input else {
            return answer(.refused, "That isn't a request Scout understands. Nothing was changed.")
        }
        switch input.request.request {
        case .status:
            return answer(.done, "Scout \(ScoutRelease.version) for \(ScoutRelease.platform).")
        case .install:
            return install(code: input.request.code)
        case .update:
            return update(statement: input.request.statement ?? "", binary: input.binary)
        case .addresses:
            return replaceAddresses(with: input.request.addresses ?? [])
        case .uninstall:
            return uninstall()
        }
    }

    private static func install(code text: String?) -> ManagementResponse {
        var said: [String] = []
        do {
            try InstallWorkflow { said.append($0) }.install(sshUser: nil) { () throws(InstallError) in
                guard let text else { return nil }
                guard let code = EnrollmentCode(text: text) else { throw .notACode }
                return code
            }
            return answer(.done, said.joined(separator: " "))
        } catch {
            return answer(outcome(of: error), InstallMessage.text(for: error))
        }
    }

    private static func update(statement: String, binary: [UInt8]) -> ManagementResponse {
        do {
            let version = try UpdateWorkflow().update(statement: statement, binary: binary)
            return answer(.done, "Updated Scout from \(ScoutRelease.version) to \(version) and restarted it.", version: version)
        } catch {
            return answer(outcome(of: error), UpdateMessage.text(for: error))
        }
    }

    private static func replaceAddresses(with addresses: [EnrollmentCode.Address]) -> ManagementResponse {
        do throws(NewAddressesError) {
            try NewAddressesWorkflow().replace(with: addresses)
            return answer(.done, "Scout has the Hive's new addresses and is connecting through them.")
        } catch {
            return answer(outcome(of: error), AddressesMessage.text(for: error))
        }
    }

    private static func uninstall() -> ManagementResponse {
        var said: [String] = []
        do {
            try UninstallWorkflow { said.append($0) }.uninstall()
            return answer(.done, said.joined(separator: " "))
        } catch {
            return answer(.failed, InstallMessage.text(for: error))
        }
    }

    private static func answer(
        _ outcome: ManagementResponse.Outcome,
        _ message: String,
        version: ScoutVersion = ScoutRelease.version
    ) -> ManagementResponse {
        ManagementResponse(outcome: outcome, version: version.description, platform: ScoutRelease.platform, message: message)
    }

    private static func outcome(of error: InstallError) -> ManagementResponse.Outcome {
        switch error {
        case .notRoot, .unknownInitSystem, .needsCode, .notACode, .sshUserNotAName, .sshUserMissing, .noSudoOrDoas,
             .enrollmentFailed:
            .refused
        case .ruleRefused, .commandFailed, .file:
            .failed
        }
    }

    private static func outcome(of error: NewAddressesError) -> ManagementResponse.Outcome {
        switch error {
        case .notRoot, .notInstalled, .notAddresses, .notSaved: .refused
        case .reloadFailed: .failed
        }
    }

    private static func outcome(of error: UpdateError) -> ManagementResponse.Outcome {
        switch error {
        case .file, .restartFailed: .failed
        default: .refused
        }
    }
}

/// What an update says when it stops.
enum UpdateMessage {
    static func text(for error: UpdateError) -> String {
        switch error {
        case .notRoot:
            "Run this as root, such as with sudo."
        case .notInstalled:
            "Scout isn't installed, so there's nothing to update. Nothing was changed."
        case .noUpdateKey:
            "This Scout was built without a key to check updates with, so it takes none. Nothing was changed."
        case .notAStatement:
            "The update's statement isn't one Scout can read. Nothing was changed."
        case .notSigned:
            "The update isn't signed with the key this Scout trusts. Nothing was changed."
        case .otherPlatform(let platform):
            "The update is for \(platform), and this server needs \(ScoutRelease.platform). Nothing was changed."
        case .hashMismatch:
            "The binary isn't the one the update's statement names. Nothing was changed."
        case let .notNewer(installed, offered):
            "The update is version \(offered), and Scout \(installed) is installed. Scout only updates to a newer version. "
                + "Nothing was changed."
        case .file(let error):
            "Couldn't write the new binary: \(error)"
        case .restartFailed(let output):
            "The new binary is in place, but Scout's service didn't start again: \(output)"
        }
    }
}

/// What a change of addresses says when it stops.
enum AddressesMessage {
    static func text(for error: NewAddressesError) -> String {
        switch error {
        case .notRoot:
            "Run this as root, such as with sudo."
        case .notInstalled:
            "Scout isn't installed, so there are no addresses to change. Nothing was changed."
        case .notAddresses:
            "Those aren't addresses Scout can use. Nothing was changed."
        case .notSaved:
            "Scout couldn't save the new addresses, as when it hasn't enrolled. Nothing was changed."
        case let .reloadFailed(command, output):
            "Scout saved the new addresses, but \(command) failed, so it uses them only once it starts again: \(output)"
        }
    }
}
