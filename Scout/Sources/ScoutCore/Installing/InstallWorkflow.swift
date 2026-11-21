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
        self.init(layout: .server, system: PosixServerSystem(), source: "/proc/self/exe", say: say)
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
        let wasInstalled = system.user(named: InstallLayout.user) != nil
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

    /// Says whether it made the user, so a first install that fails can remove it again.
    private func makeUser() throws(InstallError) -> Bool {
        let name = InstallLayout.user
        guard system.user(named: name) == nil else { return false }
        let shell = tools.find("nologin") ?? "/bin/false"
        if let useradd = tools.find("useradd") {
            let group = system.groupExists(name) ? ["--gid", name] : ["--user-group"]
            try run([useradd, "--system"] + group + ["--no-create-home", "--home-dir", layout.stateDirectory, "--shell", shell, name])
        } else if let adduser = tools.find("adduser"), let addgroup = tools.find("addgroup") {
            // BusyBox's, as on Alpine without the shadow package.
            if !system.groupExists(name) { try run([addgroup, "-S", name]) }
            try run([adduser, "-S", "-D", "-H", "-h", layout.stateDirectory, "-s", shell, "-G", name, name])
        } else {
            throw .commandFailed(command: "useradd", output: "neither useradd nor adduser is installed")
        }
        return true
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
        guard let user = system.user(named: InstallLayout.user), system.changeOwner(of: descriptor, to: user),
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
            let bytes = try InstalledFile.contents(of: source)
            return try InstalledFile.replace(layout.onDisk(layout.binary), with: bytes, mode: 0o755)
        } catch {
            throw .file(error)
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
        let name = InstallLayout.user
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
        }
        return false
    }

    private func run(_ arguments: [String]) throws(InstallError) {
        let result = system.run(arguments)
        guard result.status == 0 else { throw .commandFailed(command: arguments.joined(separator: " "), output: result.output) }
    }
}
