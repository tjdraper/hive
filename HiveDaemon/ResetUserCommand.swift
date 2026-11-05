import Darwin
import Foundation
import HiveCore

/// `sudo HiveDaemon reset-user`, run on the Hive Mac to change the account the daemon runs as.
enum ResetUserCommand {
    static func run(mode: DaemonLaunchMode) -> Never {
        guard mode == .systemDaemon else {
            fail("The development daemon runs as you and records no user.")
        }

        do {
            try RecordedUserReset().run()
        } catch RecordedUserResetError.needsRoot {
            fail("Run this with sudo.")
        } catch {
            fail("Couldn't clear the recorded user: \(error)")
        }
        print("Cleared the recorded user.")

        restartDaemon()
        print("Restarted Hive. It records the user logged in at the screen, or waits until someone logs in.")
        exit(EXIT_SUCCESS)
    }

    private static func restartDaemon() {
        guard let label = daemonLabel() else { fail("Couldn't find Hive's launchd plist beside this HiveDaemon.") }

        let launchctl = Process()
        launchctl.executableURL = URL(filePath: "/bin/launchctl")
        launchctl.arguments = ["kickstart", "-k", "system/\(label)"]
        do {
            try launchctl.run()
            launchctl.waitUntilExit()
        } catch {
            fail("Couldn't run launchctl: \(error)")
        }
        guard launchctl.terminationStatus == 0 else {
            fail("Couldn't restart Hive. It records the user logged in at the screen when it next starts.")
        }
    }

    /// Read from the plist SMAppService registered, in the app bundle holding this executable.
    private static func daemonLabel() -> String? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let plist = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Library/LaunchDaemons/HiveDaemon.plist", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: plist),
              let entries = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return entries["Label"] as? String
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(EXIT_FAILURE)
    }
}
