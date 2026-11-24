import HiveKit

/// What Add Metrics offers once Hive has checked the server: installing or enrolling Scout itself over
/// SSH, what's in the way, or the command to run as root, saying why.
enum ScoutInstallChoice: Equatable {
    case overSSH(ScoutAction, platform: ScoutRelease.Platform)
    case blocked(ScoutObstacle)
    /// `sshUser` is named in the command when Scout's rule would let Hive manage Scout from then on.
    case command(why: String?, sshUser: String?, platform: ScoutRelease.Platform?)

    init(ssh: ScoutOverSSH, server: Server) {
        guard let found = ssh.found, let platform = found.platform else {
            if let obstacle = ssh.found?.obstacle {
                self = .blocked(obstacle)
                return
            }
            let reason = ssh.check?.failure?.message(for: server) ?? ssh.checkFailure ?? "it didn't say why."
            self = .command(why: "Hive couldn't check the server, so it can't install Scout itself: \(reason)", sshUser: nil, platform: nil)
            return
        }
        if let obstacle = found.obstacle {
            self = .blocked(obstacle)
        } else if ssh.canManage {
            self = .overSSH(.enrollAgain, platform: platform)
        } else if !found.isInstalled, found.access.canInstall {
            self = .overSSH(.install, platform: platform)
        } else {
            self = Self.command(for: found, platform: platform)
        }
    }

    /// Why Hive can't do this itself, and whether the command lets it from then on.
    private static func command(for found: ScoutServerCheck, platform: ScoutRelease.Platform) -> Self {
        let user = found.sshUser
        switch found.access {
        case .none where found.hasSudoOrDoas:
            let why = "Hive signs in as \(user), which can't run commands as root. Run this once as root. It installs Scout and "
                + "lets \(user) run only Scout's own management command as root, so Beekeeper can update it from now on."
            return .command(why: why, sshUser: user, platform: platform)
        case .none:
            let why = "Hive signs in as \(user), which can't run commands as root, and the server has neither sudo nor doas. "
                + "Run this as root. Updating Scout will take a command like it too."
            return .command(why: why, sshUser: nil, platform: platform)
        default:
            let why = "Scout is installed, but didn't answer when Hive asked its version, so Hive won't replace it itself. "
                + "Run this as root to install it again."
            return .command(why: why, sshUser: nil, platform: platform)
        }
    }
}
