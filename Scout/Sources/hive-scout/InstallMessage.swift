import ScoutCore

/// What `hive-scout install` and `uninstall` say when they stop. Never the code.
enum InstallMessage {
    static func text(for error: InstallError) -> String {
        switch error {
        case .sshUserNotAName, .sshUserMissing, .noSudoOrDoas, .ruleRefused:
            sshUserText(for: error)
        case .notRoot:
            "Run this as root, such as with sudo."
        case .unknownInitSystem:
            "This server doesn't run systemd or OpenRC, so Scout can't install a service. Nothing was installed. "
                + "Your init system can run hive-scout run as the \(InstallLayout.server.user) user itself."
        case .binaryFolderNotRoots(let folder):
            "Users other than root can change \(folder), as Homebrew on an Intel Mac leaves it, so they could replace "
                + "Scout's binary, which runs as root. Nothing was installed."
        case .needsCode:
            "Scout isn't installed yet, so it needs an enrollment code from Beekeeper. Nothing was installed."
        case .notACode:
            "That isn't a whole enrollment code. Copy it again from Beekeeper. Nothing was changed."
        case .enrollmentFailed:
            "Scout couldn't enroll, so nothing was installed or changed."
        case let .commandFailed(command, output):
            "\(command) failed: \(output)"
        case .file(let error):
            "Couldn't write Scout's files: \(error)"
        }
    }

    private static func sshUserText(for error: InstallError) -> String {
        switch error {
        case .sshUserMissing(let name):
            "There's no user named \(name) on this server. Nothing was changed."
        case .noSudoOrDoas:
            "--ssh-user needs sudo or doas, and neither is installed. Nothing was changed."
        case .ruleRefused(let output):
            "The rule for Hive's SSH user didn't pass its check, so it was left out: \(output)"
        default:
            "--ssh-user takes a user name of letters, digits, '.', '_' and '-', not starting with '-' "
                + "and not in capitals alone. Nothing was changed."
        }
    }
}
