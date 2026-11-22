/// One request to `hive-scout manage`, which Hive runs as root over SSH, through `sudo` or `doas`
/// where its user has only Scout's rule. It takes no arguments, so the rule never has to allow any:
/// the request is one line of JSON on standard input, and an update's binary follows that line,
/// `binaryLength` bytes of it, and nothing after.
public struct ManagementRequest: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Says which version is installed, changing nothing.
        case status
        /// Installs the binary that's running, or with a code for a server already installed,
        /// enrolls it again. Without a code, keeps the enrollment the server has.
        case install
        /// Replaces the installed binary with a newer release, signed with Scout's update key.
        case update
        case uninstall
    }

    /// The request line, with its statement and code, fits in this.
    public static let longestLine = 8192
    /// Far larger than Scout's binary, which is about 20 MB.
    public static let largestBinary = 64 << 20

    public let request: Kind
    /// For `install`.
    public let code: String?
    /// For `update`: the release's signed statement, as its file holds it.
    public let statement: String?
    /// For `update`.
    public let binaryLength: Int?

    public static let status = Self(request: .status)
    public static let uninstall = Self(request: .uninstall)

    public static func install(code: String?) -> Self {
        Self(request: .install, code: code)
    }

    public static func update(statement: String, binaryLength: Int) -> Self {
        Self(request: .update, statement: statement, binaryLength: binaryLength)
    }

    private init(request: Kind, code: String? = nil, statement: String? = nil, binaryLength: Int? = nil) {
        self.request = request
        self.code = code
        self.statement = statement
        self.binaryLength = binaryLength
    }
}

/// What `hive-scout manage` answers, as one line of JSON on standard output.
public struct ManagementResponse: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case done
        /// Nothing was changed.
        case refused
        /// Something may have changed before it stopped, such as a binary replaced whose service
        /// didn't start again.
        case failed
    }

    public let outcome: Outcome
    /// The version installed once the request is done: the new one after an update.
    public let version: String
    public let platform: String
    /// What happened, or why not, for people. It never holds the enrollment code.
    public let message: String

    public init(outcome: Outcome, version: String, platform: String, message: String) {
        self.outcome = outcome
        self.version = version
        self.platform = platform
        self.message = message
    }
}
