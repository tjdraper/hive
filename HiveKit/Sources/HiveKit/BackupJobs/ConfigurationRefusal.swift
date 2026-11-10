/// Sent with 422 when Hive turns down a server, a job or the email settings, which then changes nothing. It lists every
/// problem found, so Beekeeper can show each beside its field. A problem never repeats the value sent.
public struct ConfigurationRefusal: Codable, Hashable, Sendable {
    public let problems: [ConfigurationProblem]

    public init(problems: [ConfigurationProblem]) {
        self.problems = problems
    }
}

public struct ConfigurationProblem: Codable, Hashable, Sendable {
    public let field: ConfigurationField
    /// The directory, database or time it's about, by its place in the list sent.
    public let index: Int?
    public let reason: ConfigurationProblemReason

    public init(field: ConfigurationField, index: Int? = nil, reason: ConfigurationProblemReason) {
        self.field = field
        self.index = index
        self.reason = reason
    }
}

public enum ConfigurationField: String, Codable, Hashable, Sendable {
    case name
    case host
    case port
    case user
    case quota
    case directories
    case directoryPath
    case directoryFolder
    /// A database's ID, which has to be one the job already has.
    case database
    case databaseName
    case databaseUser
    case databaseServiceName
    case databasePassword
    case times
    case time
    case dailySnapshots
    case monthlySnapshots
    case senderAddress
    /// The email settings' list of recipients as a whole, such as when it's empty.
    case recipients
    /// One of the email settings' recipients.
    case recipient
    case password
}

public enum ConfigurationProblemReason: String, Codable, Hashable, Sendable {
    /// Empty, too long, or holding characters the field can't, such as a host or user starting with `-`.
    case invalid
    case outOfRange
    /// Another server or another of the server's jobs has the name, or it's repeated within the job.
    case duplicate
    /// A directory's path on the server has to start with `/`.
    case notAbsolute
    /// A folder in the snapshot can't start with `/`.
    case notRelative
    /// A folder with an empty part, such as `images//galleries` or `images/`.
    case emptyPart
    /// A folder with a `.` or `..` part.
    case dotPart
    /// A folder inside another of the job's folders, which the other's backup would delete.
    case insideAnother
    /// A database ID the job doesn't have.
    case unknown
    /// A job with no times to run, email with no recipients, or a username with no password.
    case missing
    /// A job with neither directories nor databases.
    case nothingToBackUp
}
