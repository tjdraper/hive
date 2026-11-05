import Darwin
import SystemConfiguration

public protocol ConsoleUserFinding {
    /// The account logged in at the Mac's screen, or nil when nobody is.
    func consoleUserID() -> uid_t?
}

public struct ConsoleUserFinder: ConsoleUserFinding {
    public init() {}

    public func consoleUserID() -> uid_t? {
        var userID: uid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &userID, nil) as String? else { return nil }
        // At the login window the console belongs to loginwindow, not to a person.
        return name == "loginwindow" ? nil : userID
    }
}
