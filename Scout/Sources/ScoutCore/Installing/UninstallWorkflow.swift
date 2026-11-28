#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// `hive-scout uninstall`, run as root: stops and removes the service, the binary, the management
/// rule, the state folder and Scout's user.
public struct UninstallWorkflow {
    let layout: InstallLayout
    let system: any ServerSystem
    let say: (String) -> Void

    public init(say: @escaping (String) -> Void) {
        self.init(layout: .server, system: PosixServerSystem(), say: say)
    }

    init(layout: InstallLayout, system: any ServerSystem, say: @escaping (String) -> Void) {
        self.layout = layout
        self.system = system
        self.say = say
    }

    private var tools: ServerTools {
        ServerTools(layout: layout)
    }

    public func uninstall() throws(InstallError) {
        guard system.isRoot else { throw .notRoot }
        try stopService()
        do {
            for path in [layout.sudoRule, layout.doasRule, layout.binary] {
                try InstalledFile.remove(layout.onDisk(path))
            }
        } catch {
            throw .file(error)
        }
        try removeStateFolder()
        // OpenRC's folder; systemd removes its own when the service stops, and a Mac's is the state folder.
        try remove(folder: layout.runtimeDirectory)
        try removeUser()
        say("Uninstalled Scout.")
    }

    /// Stops the service first, so none of Scout's processes is left to change the state folder while
    /// it's removed, or to keep its user from being removed.
    private func stopService() throws(InstallError) {
        let name = layout.user
        let unit = layout.onDisk(layout.systemdUnit)
        if access(unit, F_OK) == 0 {
            let systemctl = tools.find("systemctl") ?? "systemctl"
            // Fails when systemd isn't running, as in a container, which leaves nothing to stop.
            _ = system.run([systemctl, "disable", "--now", "--quiet", name])
            try removeFile(unit)
            _ = system.run([systemctl, "daemon-reload"])
        }
        let script = layout.onDisk(layout.openRCScript)
        if access(script, F_OK) == 0 {
            _ = system.run([tools.find("rc-service") ?? "rc-service", name, "stop"])
            _ = system.run([tools.find("rc-update") ?? "rc-update", "del", name, "default"])
            try removeFile(script)
        }
        let daemon = layout.onDisk(layout.launchDaemon)
        if access(daemon, F_OK) == 0 {
            // Fails when it isn't loaded, which leaves nothing to stop.
            _ = system.run([tools.find("launchctl") ?? "launchctl", "bootout", InitSystem.launchdTarget])
            try removeFile(daemon)
        }
    }

    func removeStateFolder() throws(InstallError) {
        try remove(folder: layout.stateDirectory)
    }

    func removeUser() throws(InstallError) {
        let name = layout.user
        if layout.system == .mac {
            let dscl = tools.find("dscl") ?? "dscl"
            if system.user(named: name) != nil { try run([dscl, ".", "-delete", "/Users/\(name)"]) }
            if system.groupID(named: name) != nil { try run([dscl, ".", "-delete", "/Groups/\(name)"]) }
            return
        }
        if let user = system.user(named: name) {
            // A systemd user manager, kept by lingering or a login, still runs as the user, and
            // userdel refuses a user with processes.
            if let loginctl = tools.find("loginctl"), let systemctl = tools.find("systemctl") {
                _ = system.run([loginctl, "disable-linger", name])
                _ = system.run([systemctl, "stop", "user@\(user.uid).service"])
            }
            let command = tools.find("userdel").map { [$0, name] } ?? [tools.find("deluser") ?? "deluser", name]
            try run(command)
        }
        // userdel removes the user's own group on most distributions, but not all.
        if system.groupID(named: name) != nil {
            try run(tools.find("groupdel").map { [$0, name] } ?? [tools.find("delgroup") ?? "delgroup", name])
        }
    }

    private func removeFile(_ path: String) throws(InstallError) {
        do {
            try InstalledFile.remove(path)
        } catch {
            throw .file(error)
        }
    }

    /// Removes a folder Scout's user owns and all it holds, following no link inside it.
    private func remove(folder path: String) throws(InstallError) {
        let onDisk = layout.onDisk(path)
        let descriptor = open(onDisk, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return }
            throw .file(.couldNotRemove(path: onDisk, errno: errno))
        }
        guard Self.removeContents(of: descriptor), rmdir(onDisk) == 0 else {
            throw .file(.couldNotRemove(path: onDisk, errno: errno))
        }
    }

    /// Takes ownership of `descriptor`, an open folder, and closes it.
    private static func removeContents(of descriptor: Int32) -> Bool {
        guard let folder = fdopendir(descriptor) else {
            SystemFiles.close(descriptor)
            return false
        }
        defer { closedir(folder) }
        // As the bytes the folder holds, so a name that isn't UTF-8 is still removed.
        var names: [[CChar]] = []
        while let entry = readdir(folder) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                Array(bytes.bindMemory(to: CChar.self).prefix { $0 != 0 }) + [0]
            }
            if name != [46, 0], name != [46, 46, 0] { names.append(name) }
        }
        for name in names where unlinkat(descriptor, name, 0) != 0 {
            guard errno == EISDIR || errno == EPERM else { return false }
            let inner = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard inner >= 0, removeContents(of: inner), unlinkat(descriptor, name, AT_REMOVEDIR) == 0 else { return false }
        }
        return true
    }

    private func run(_ arguments: [String]) throws(InstallError) {
        let result = system.run(arguments)
        guard result.status == 0 else { throw .commandFailed(command: arguments.joined(separator: " "), output: result.output) }
    }
}
