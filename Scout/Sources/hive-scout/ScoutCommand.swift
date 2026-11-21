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

    static let usage = """
        usage: hive-scout sample
               hive-scout watch [--tls <host>:<port> --pin <SHA-256 of Hive's key, in hex>]
               hive-scout enroll [--state-directory <path>] < code
        """

    init?(arguments: [String]) {
        switch arguments.first {
        case "sample" where arguments.count == 1:
            self = .sample
        case "watch":
            guard let target = Self.hiveTarget(from: arguments.dropFirst()) else { return nil }
            self = .watch(target)
        case "enroll":
            // Never the code itself, which an argument would show in `ps`, `sudo`'s log and the journal.
            switch arguments.count {
            case 1: self = .enroll(stateDirectory: EnrollmentStore.defaultDirectory)
            case 3 where arguments[1] == "--state-directory" && arguments[2].hasPrefix("/"):
                self = .enroll(stateDirectory: arguments[2])
            default: return nil
            }
        default:
            return nil
        }
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
