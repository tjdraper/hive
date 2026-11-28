#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import ScoutProtocol

public enum InstallError: Error, Equatable {
    case notRoot
    case unknownInitSystem
    /// Someone other than root can change the binary's folder, so a binary root runs from there could
    /// be replaced, as Homebrew on an Intel Mac leaves `/usr/local/bin`.
    case binaryFolderNotRoots(String)
    /// Running install the first time, or after uninstalling, needs a code.
    case needsCode
    case notACode
    case sshUserNotAName(String)
    case sshUserMissing(String)
    case noSudoOrDoas
    /// `visudo` or `doas` found a fault in the rule, which was left out.
    case ruleRefused(output: String)
    /// The enrolling Scout has said why itself.
    case enrollmentFailed
    case commandFailed(command: String, output: String)
    case file(InstalledFileError)
}

/// `hive-scout install`, run as root: puts this binary in place, makes Scout's user and state folder,
/// enrolls as that user, and writes and starts the service. Run again, it replaces the binary and
/// restarts the service, keeping the enrollment unless given a new code.
///
/// Root never reads Scout's state folder: `hive-scout` owns it and runs the code that talks to the
/// network, so what's in it can't be trusted. Enrolling runs as a program of its own that drops to
/// Scout's user first.
public struct InstallWorkflow {
    let layout: InstallLayout
    let system: any ServerSystem
    /// The binary to install, as this machine sees it.
    let source: String
    let say: (String) -> Void

    public init(say: @escaping (String) -> Void) {
        self.init(layout: .server, system: PosixServerSystem(), source: ScoutRelease.executablePath, say: say)
    }

    init(layout: InstallLayout, system: any ServerSystem, source: String, say: @escaping (String) -> Void) {
        self.layout = layout
        self.system = system
        self.source = source
        self.say = say
    }

    private var tools: ServerTools {
        ServerTools(layout: layout)
    }

    /// - Parameter readCode: reads the enrollment code, once the checks that need none have passed.
    ///   Nil keeps the enrollment the server has.
    public func install(sshUser: String?, readCode: () throws(InstallError) -> EnrollmentCode?) throws(InstallError) {
        guard system.isRoot else { throw .notRoot }
        guard let initSystem = InitSystem.running(in: layout, tools: tools) else { throw .unknownInitSystem }
        let rule = try sshUser.map { name throws(InstallError) in try managementRule(for: name) }
        try checkBinaryFolder()
        let wasInstalled = system.user(named: layout.user) != nil
            && access(layout.onDisk(initSystem.servicePath(in: layout)), F_OK) == 0

        let code = try readCode()
        guard code != nil || wasInstalled else { throw .needsCode }

        let createdUser = try makeUser()
        let createdFolder = try makeStateFolder()
        if let code {
            guard system.enroll(code: code.text, binary: source, stateDirectory: layout.stateDirectory) else {
                if !wasInstalled { removeWhatWasMade(user: createdUser, folder: createdFolder) }
                throw .enrollmentFailed
            }
        }

        let binaryChanged = try copyBinary()
        let service = initSystem.serviceFile(for: layout)
        let serviceChanged = try replace(initSystem.servicePath(in: layout), with: service.text, mode: service.mode)
        if let rule { try write(rule.rule, for: rule.user) }
        let onlyEnrolledAgain = code != nil && wasInstalled && !binaryChanged && !serviceChanged
        let reloaded = try start(initSystem, serviceChanged: serviceChanged, reloadOnly: onlyEnrolledAgain)

        let version = ScoutRelease.version
        if reloaded {
            say("Scout \(version) is sending with its new enrollment.")
        } else {
            say(wasInstalled ? "Updated Scout \(version) and restarted it." : "Installed Scout \(version) and started it.")
        }
        if let rule {
            let tool = rule.rule == .sudo ? "sudo" : "doas"
            say("\(rule.user.text) can run \(layout.binary) manage as root through \(tool), and nothing else.")
        }
        let mounts = SystemFiles(root: layout.root).text(at: "/proc/self/mountinfo").map(Mount.all(parsing:)) ?? []
        if mounts.processesHidden {
            say("/proc is mounted with hidepid, so Scout can't see other users' processes. It sends everything else.")
        }
    }

    private func managementRule(for name: String) throws(InstallError) -> (rule: ManagementRule, user: SSHUserName) {
        guard let user = SSHUserName(name) else { throw .sshUserNotAName(name) }
        guard system.user(named: user.text) != nil else { throw .sshUserMissing(user.text) }
        if tools.find("sudo") != nil, tools.find("visudo") != nil { return (.sudo, user) }
        if tools.find("doas") != nil { return (.doas, user) }
        throw .noSudoOrDoas
    }

    /// The binary's folder, or the nearest folder above it that's there, since installing makes the rest.
    private func checkBinaryFolder() throws(InstallError) {
        var folder = layout.binary
        repeat {
            folder = String(folder[..<(folder.lastIndex(of: "/") ?? folder.startIndex)])
        } while !folder.isEmpty && access(layout.onDisk(folder), F_OK) != 0
        guard system.onlyRootCanChange(folder: layout.onDisk(folder.isEmpty ? "/" : folder)) else {
            throw .binaryFolderNotRoots(folder)
        }
    }

    /// Says whether it made the user, so a first install that fails can remove it again.
    private func makeUser() throws(InstallError) -> Bool {
        let name = layout.user
        guard system.user(named: name) == nil else { return false }
        if layout.system == .mac {
            try makeMacUser(named: name)
            return true
        }
        let shell = tools.find("nologin") ?? "/bin/false"
        if let useradd = tools.find("useradd") {
            let group = system.groupID(named: name) != nil ? ["--gid", name] : ["--user-group"]
            try run([useradd, "--system"] + group + ["--no-create-home", "--home-dir", layout.stateDirectory, "--shell", shell, name])
        } else if let adduser = tools.find("adduser"), let addgroup = tools.find("addgroup") {
            // BusyBox's, as on Alpine without the shadow package.
            if system.groupID(named: name) == nil { try run([addgroup, "-S", name]) }
            try run([adduser, "-S", "-D", "-H", "-h", layout.stateDirectory, "-s", shell, "-G", name, name])
        } else {
            throw .commandFailed(command: "useradd", output: "neither useradd nor adduser is installed")
        }
        return true
    }

    /// A hidden system user, and a group of its own, with an ID below a Mac's first person's (501),
    /// from the top down, since macOS's own system users are mostly lower.
    private func makeMacUser(named name: String) throws(InstallError) {
        let dscl = tools.find("dscl") ?? "dscl"
        guard let free = (300...499).reversed().first(where: { !system.idInUse(UInt32($0)) }) else {
            throw .commandFailed(command: "dscl", output: "no ID between 300 and 499 is free for a system user")
        }
        let groupID: UInt32
        if let existing = system.groupID(named: name) {
            groupID = existing
        } else {
            groupID = UInt32(free)
            for (key, value) in [("PrimaryGroupID", "\(groupID)"), ("RealName", "Hive Scout"), ("Password", "*")] {
                try run([dscl, ".", "-create", "/Groups/\(name)", key, value])
            }
        }
        let fields = [
            ("UniqueID", "\(free)"), ("PrimaryGroupID", "\(groupID)"), ("UserShell", "/usr/bin/false"),
            ("NFSHomeDirectory", "/var/empty"), ("RealName", "Hive Scout"), ("Password", "*"), ("IsHidden", "1"),
        ]
        for (key, value) in fields {
            try run([dscl, ".", "-create", "/Users/\(name)", key, value])
        }
    }

    /// Makes the folder if it's missing and gives it to Scout's user, without looking inside it.
    /// Says whether it made it.
    private func makeStateFolder() throws(InstallError) -> Bool {
        let path = layout.onDisk(layout.stateDirectory)
        let created = mkdir(path, 0o700) == 0
        guard created || errno == EEXIST else { throw .file(.couldNotWrite(path: path, errno: errno)) }
        // Never a link someone left in its place.
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw .file(.couldNotWrite(path: path, errno: errno)) }
        defer { SystemFiles.close(descriptor) }
        guard let user = system.user(named: layout.user), system.changeOwner(of: descriptor, to: user),
              fchmod(descriptor, 0o700) == 0
        else { throw .file(.couldNotWrite(path: path, errno: errno)) }
        return created
    }

    private func removeWhatWasMade(user: Bool, folder: Bool) {
        let uninstall = UninstallWorkflow(layout: layout, system: system, say: say)
        if folder { try? uninstall.removeStateFolder() }
        if user { try? uninstall.removeUser() }
    }

    private func copyBinary() throws(InstallError) -> Bool {
        do {
            try makeBinaryFolder()
            let bytes = try InstalledFile.contents(of: source)
            return try InstalledFile.replace(layout.onDisk(layout.binary), with: bytes, mode: 0o755)
        } catch {
            throw .file(error)
        }
    }

    /// A Mac may have no `/usr/local/bin` yet.
    private func makeBinaryFolder() throws(InstalledFileError) {
        var folder = ""
        for part in layout.binary.split(separator: "/").dropLast() {
            folder += "/\(part)"
            let path = layout.onDisk(folder)
            guard access(path, F_OK) == 0 || mkdir(path, 0o755) == 0 else { throw .couldNotWrite(path: path, errno: errno) }
        }
    }

    private func replace(_ path: String, with text: String, mode: mode_t) throws(InstallError) -> Bool {
        do {
            return try InstalledFile.replace(layout.onDisk(path), with: Array(text.utf8), mode: mode)
        } catch {
            throw .file(error)
        }
    }

    /// Checked by `visudo` or `doas` before it's put in place, since a rule with a fault can stop
    /// `sudo` working for everyone.
    private func write(_ rule: ManagementRule, for user: SSHUserName) throws(InstallError) {
        let path = layout.onDisk(rule.path(in: layout))
        let text = Array(rule.text(for: user, binary: layout.binary).utf8)
        guard !InstalledFile.holds(text, at: path) else { return }
        let staged: String
        do {
            staged = try InstalledFile.stage(text, for: path, mode: 0o440)
        } catch {
            throw .file(error)
        }
        let check = switch rule {
        case .sudo: [tools.find("visudo") ?? "visudo", "-c", "-q", "-f", staged]
        case .doas: [tools.find("doas") ?? "doas", "-C", staged]
        }
        let result = system.run(check)
        guard result.status == 0 else {
            unlink(staged)
            throw .ruleRefused(output: result.output)
        }
        do {
            try InstalledFile.putInPlace(staged, at: path)
        } catch {
            throw .file(error)
        }
    }

    /// Says whether a reload was enough, without a restart.
    private func start(_ initSystem: InitSystem, serviceChanged: Bool, reloadOnly: Bool) throws(InstallError) -> Bool {
        let name = layout.user
        switch initSystem {
        case .systemd:
            let systemctl = tools.find("systemctl") ?? "systemctl"
            if serviceChanged { try run([systemctl, "daemon-reload"]) }
            try run([systemctl, "enable", "--quiet", name])
            // A reload reads the new enrollment and connects at once, keeping what Scout holds.
            if reloadOnly, system.run([systemctl, "reload", name]).status == 0 { return true }
            try run([systemctl, "restart", name])
        case .openRC:
            try run([tools.find("rc-update") ?? "rc-update", "add", name, "default"])
            let rcService = tools.find("rc-service") ?? "rc-service"
            if reloadOnly, system.run([rcService, name, "reload"]).status == 0 { return true }
            try run([rcService, name, "restart"])
        case .launchd:
            let launchctl = tools.find("launchctl") ?? "launchctl"
            let target = InitSystem.launchdTarget
            let loaded = system.run([launchctl, "print", target]).status == 0
            // `run` passes the signal on to the process that sends.
            if reloadOnly, loaded, system.run([launchctl, "kill", "SIGHUP", target]).status == 0 { return true }
            if serviceChanged || !loaded {
                // launchd reads the file only when it's loaded.
                if loaded { try run([launchctl, "bootout", target]) }
                try run([launchctl, "enable", target])
                try run([launchctl, "bootstrap", "system", layout.launchDaemon])
            } else {
                try run([launchctl, "kickstart", "-k", target])
            }
        }
        return false
    }

    private func run(_ arguments: [String]) throws(InstallError) {
        let result = system.run(arguments)
        guard result.status == 0 else { throw .commandFailed(command: arguments.joined(separator: " "), output: result.output) }
    }
}
