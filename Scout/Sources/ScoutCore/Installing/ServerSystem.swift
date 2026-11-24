#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

struct SystemUser: Equatable {
    let uid: uid_t
    let gid: gid_t
}

struct CommandResult: Equatable {
    let status: Int32
    /// Standard output and standard error together.
    let output: String
}

/// What installing does that needs root or another program, apart from writing files, so tests can
/// stand in for it.
protocol ServerSystem {
    var isRoot: Bool { get }
    func user(named name: String) -> SystemUser?
    func groupExists(_ name: String) -> Bool
    /// Runs a program by its absolute path, without a shell.
    func run(_ arguments: [String]) -> CommandResult
    /// Runs `binary enroll` with the code on standard input. Run as root, `enroll` drops to Scout's
    /// user itself before reading anything, and its messages go straight to the terminal.
    func enroll(code: String, binary: String, stateDirectory: String) -> Bool
    /// Runs `binary addresses` with the addresses as JSON on standard input, which drops to Scout's
    /// user, as `enroll` does.
    func replaceAddresses(json: [UInt8], binary: String, stateDirectory: String) -> Bool
    func changeOwner(of descriptor: Int32, to user: SystemUser) -> Bool
}

/// Finds the programs installing runs, by their usual places rather than `PATH`, which `sudo` may set
/// to anything.
struct ServerTools {
    static let folders = ["/usr/sbin", "/usr/bin", "/sbin", "/bin"]

    let layout: InstallLayout

    /// The program's path as the server sees it, or nil when it isn't there.
    func find(_ name: String) -> String? {
        Self.folders.map { "\($0)/\(name)" }.first { access(layout.onDisk($0), X_OK) == 0 }
    }
}

/// The server's own users and programs.
struct PosixServerSystem: ServerSystem {
    /// Programs run by installing get only what they need from the environment `sudo` gave Scout.
    private static let environment = ["PATH=/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL=C"]

    init() {}

    var isRoot: Bool {
        geteuid() == 0
    }

    func user(named name: String) -> SystemUser? {
        getpwnam(name).map { SystemUser(uid: $0.pointee.pw_uid, gid: $0.pointee.pw_gid) }
    }

    func groupExists(_ name: String) -> Bool {
        getgrnam(name) != nil
    }

    func run(_ arguments: [String]) -> CommandResult {
        var output: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return CommandResult(status: -1, output: "couldn't make a pipe (errno \(errno))") }
        let pid = Self.spawn(arguments) { actions in
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
            posix_spawn_file_actions_adddup2(&actions, output[1], STDERR_FILENO)
            posix_spawn_file_actions_addclose(&actions, output[0])
            posix_spawn_file_actions_addclose(&actions, output[1])
        }
        Self.closeDescriptor(output[1])
        defer { Self.closeDescriptor(output[0]) }
        guard let pid else { return CommandResult(status: -1, output: "couldn't start \(arguments[0]) (errno \(errno))") }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Self.readDescriptor(output[0], $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            bytes += buffer[..<count]
        }
        // swiftlint:disable:next optional_data_string_conversion
        return CommandResult(status: Self.wait(for: pid), output: String(decoding: bytes, as: UTF8.self))
    }

    func enroll(code: String, binary: String, stateDirectory: String) -> Bool {
        Self.run(binary, ["enroll", "--state-directory", stateDirectory], input: Array((code + "\n").utf8))
    }

    func replaceAddresses(json: [UInt8], binary: String, stateDirectory: String) -> Bool {
        Self.run(binary, ["addresses", "--state-directory", stateDirectory], input: json + [UInt8(ascii: "\n")])
    }

    /// Whether `binary` with `arguments` exited successfully, its messages going straight to the terminal.
    private static func run(_ binary: String, _ arguments: [String], input line: [UInt8]) -> Bool {
        // The input is written before the program starts, so it waits in the pipe however soon the
        // program exits, and writing can't fail with SIGPIPE. It's far smaller than a pipe holds.
        var input: [Int32] = [-1, -1]
        guard pipe(&input) == 0 else { return false }
        let written = line.withUnsafeBytes { writeDescriptor(input[1], $0.baseAddress, $0.count) }
        closeDescriptor(input[1])
        defer { closeDescriptor(input[0]) }
        guard written == line.count else { return false }
        let pid = spawn([binary] + arguments, program: binary) { actions in
            posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
            posix_spawn_file_actions_addclose(&actions, input[0])
        }
        guard let pid else { return false }
        return wait(for: pid) == 0
    }

    func changeOwner(of descriptor: Int32, to user: SystemUser) -> Bool {
        fchown(descriptor, user.uid, user.gid) == 0
    }

    #if canImport(Darwin)
    private typealias FileActions = posix_spawn_file_actions_t?
    #else
    private typealias FileActions = posix_spawn_file_actions_t
    #endif

    /// Starts `program`, which is `arguments[0]` unless given, with the arguments as its own.
    private static func spawn(
        _ arguments: [String],
        program: String? = nil,
        actions setUp: (inout FileActions) -> Void
    ) -> pid_t? {
        #if canImport(Darwin)
        var actions: FileActions = nil
        #else
        var actions = FileActions()
        #endif
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        setUp(&actions)
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid = pid_t()
        guard posix_spawn(&pid, program ?? arguments[0], &actions, nil, argv, envp) == 0 else { return nil }
        return pid
    }

    /// The program's exit status, or -1 when a signal ended it.
    private static func wait(for pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            guard errno == EINTR else { return -1 }
        }
        return status & 0x7F == 0 ? (status >> 8) & 0xFF : -1
    }

    private static func readDescriptor(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.read(descriptor, buffer, count)
        #elseif canImport(Glibc)
        Glibc.read(descriptor, buffer, count)
        #else
        Musl.read(descriptor, buffer, count)
        #endif
    }

    private static func writeDescriptor(_ descriptor: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(descriptor, buffer, count)
        #elseif canImport(Glibc)
        Glibc.write(descriptor, buffer, count)
        #else
        Musl.write(descriptor, buffer, count)
        #endif
    }

    private static func closeDescriptor(_ descriptor: Int32) {
        SystemFiles.close(descriptor)
    }
}
