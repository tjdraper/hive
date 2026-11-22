import ScoutCore

/// What `hive-scout` was asked to do, from its arguments.
enum ScoutCommand: Equatable {
    struct HiveTarget: Equatable {
        let address: HiveAddress
        let pin: HiveKeyPin
    }

    /// Prints one sample as JSON.
    case sample
    /// Prints a sample every 10 seconds, holding a connection to Hive open when given one.
    case watch(HiveTarget?)
    /// Enrolls with a Hive through a code read from standard input, saving the key in the folder.
    case enroll(stateDirectory: String)
    /// Samples every 10 seconds and sends to the Hive it enrolled with, as the service does.
    case run(stateDirectory: String, runtimeDirectory: String)
    /// Prints whether the running Scout is sending, from its runtime folder.
    case status(runtimeDirectory: String)
    /// Installs this binary as a service, run as root, enrolling through a code read from standard
    /// input, and lets Hive's SSH user run Scout's management command as root when named.
    case install(sshUser: String?)
    case uninstall
    /// Carries out one `ManagementRequest` from standard input, run as root by Hive over SSH. It
    /// takes no arguments, so the `sudo` and `doas` rules allow none.
    case manage

    static let usage = """
        usage: hive-scout sample
               hive-scout watch [--tls <host>:<port> --pin <SHA-256 of Hive's key, in hex>]
               hive-scout enroll [--state-directory <path>] < code
               hive-scout run [--state-directory <path>] [--runtime-directory <path>]
               hive-scout status [--runtime-directory <path>]
               sudo hive-scout install [--ssh-user <name>] < code
               sudo hive-scout uninstall
               sudo hive-scout manage < request
        """

    init?(arguments: [String]) {
        let options = arguments.dropFirst()
        switch arguments.first {
        case "sample" where options.isEmpty:
            self = .sample
        case "watch":
            guard let target = Self.hiveTarget(from: options) else { return nil }
            self = .watch(target)
        case "install":
            guard let sshUser = Self.sshUser(from: options) else { return nil }
            self = .install(sshUser: sshUser)
        case "uninstall" where options.isEmpty:
            self = .uninstall
        case "manage" where options.isEmpty:
            self = .manage
        case let name?:
            guard let command = Self.withFolders(name, options: options) else { return nil }
            self = command
        default:
            return nil
        }
    }

    /// Commands that take only folders as options.
    private static func withFolders(_ name: String, options: ArraySlice<String>) -> Self? {
        switch name {
        case "enroll":
            // Never the code itself, which an argument would show in `ps`, `sudo`'s log and the journal.
            guard let folders = folders(from: options, allowed: ["--state-directory"]) else { return nil }
            return .enroll(stateDirectory: folders["--state-directory"] ?? EnrollmentStore.defaultDirectory)
        case "run":
            guard let folders = folders(from: options, allowed: ["--state-directory", "--runtime-directory"]) else { return nil }
            return .run(
                stateDirectory: folders["--state-directory"] ?? EnrollmentStore.defaultDirectory,
                runtimeDirectory: folders["--runtime-directory"] ?? SendingStatusFile.defaultDirectory
            )
        case "status":
            guard let folders = folders(from: options, allowed: ["--runtime-directory"]) else { return nil }
            return .status(runtimeDirectory: folders["--runtime-directory"] ?? SendingStatusFile.defaultDirectory)
        default:
            return nil
        }
    }

    /// The name is checked when installing, so a wrong one is refused with a reason.
    private static func sshUser(from options: ArraySlice<String>) -> String?? {
        guard !options.isEmpty else { return .some(nil) }
        guard options.count == 2, options.first == "--ssh-user" else { return nil }
        return .some(options.last)
    }

    /// Options naming folders, each at most once and as an absolute path. Nil for anything else.
    private static func folders(from options: ArraySlice<String>, allowed: Set<String>) -> [String: String]? {
        guard options.count.isMultiple(of: 2) else { return nil }
        var folders: [String: String] = [:]
        for index in stride(from: options.startIndex, to: options.endIndex, by: 2) {
            let (name, path) = (options[index], options[index + 1])
            guard allowed.contains(name), folders[name] == nil, path.hasPrefix("/") else { return nil }
            folders[name] = path
        }
        return folders
    }

    /// The target is optional, but `--tls` is never accepted without a `--pin` to check Hive against.
    private static func hiveTarget(from options: ArraySlice<String>) -> HiveTarget?? {
        guard !options.isEmpty else { return .some(nil) }
        guard options.count == 4 else { return nil }
        var values: [String: String] = [:]
        for index in stride(from: options.startIndex, to: options.endIndex, by: 2) {
            values[options[index]] = options[index + 1]
        }
        guard let address = values["--tls"].flatMap(HiveAddress.init(parsing:)),
              let pin = values["--pin"].flatMap(HiveKeyPin.init(hex:))
        else { return nil }
        return .some(HiveTarget(address: address, pin: pin))
    }
}
