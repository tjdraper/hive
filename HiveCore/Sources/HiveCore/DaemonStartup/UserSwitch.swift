import Darwin
import Foundation

public enum UserSwitchError: Error, Equatable {
    case couldNotSetGroups(errno: Int32)
    case couldNotSetGroupID(errno: Int32)
    case couldNotSetUserID(errno: Int32)
    case identityUnchanged
    case rootStillAvailable
}

/// Gives up root for good. The group calls come first, because only root may make them.
public struct UserSwitch {
    let process: any ProcessIdentity

    public init(process: any ProcessIdentity) {
        self.process = process
    }

    public func become(_ account: UserAccount) throws {
        guard process.initializeGroups(name: account.name, groupID: account.groupID) == 0 else {
            throw UserSwitchError.couldNotSetGroups(errno: process.lastError)
        }
        guard process.setGroupID(account.groupID) == 0 else {
            throw UserSwitchError.couldNotSetGroupID(errno: process.lastError)
        }
        guard process.setUserID(account.userID) == 0 else {
            throw UserSwitchError.couldNotSetUserID(errno: process.lastError)
        }

        guard process.userID == account.userID,
              process.effectiveUserID == account.userID,
              process.groupID == account.groupID,
              process.effectiveGroupID == account.groupID
        else { throw UserSwitchError.identityUnchanged }

        guard process.setUserID(0) != 0, process.setEffectiveUserID(0) != 0 else {
            throw UserSwitchError.rootStillAvailable
        }

        // launchd starts the daemon with root's environment, which child processes would inherit.
        process.setEnvironment("HOME", account.homeDirectory.fileSystemPath)
        process.setEnvironment("USER", account.name)
        process.setEnvironment("LOGNAME", account.name)
    }
}
