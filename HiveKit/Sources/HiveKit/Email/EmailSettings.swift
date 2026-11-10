/// How Hive sends email: through the person's own provider, over TLS (§13).
public struct EmailSettings: Codable, Hashable, Sendable {
    /// A DNS name, never an address, so the certificate can be checked against it.
    public var host: String
    public var port: Int
    public var security: EmailSecurity
    /// Empty for a server that takes mail without signing in.
    public var username: String
    /// What Hive's email comes from, shown with the Hive's name.
    public var senderAddress: String
    public var recipients: [String]

    public init(host: String, port: Int, security: EmailSecurity, username: String, senderAddress: String, recipients: [String]) {
        self.host = host
        self.port = port
        self.security = security
        self.username = username
        self.senderAddress = senderAddress
        self.recipients = recipients
    }
}

/// Hive never sends anything, the password included, before TLS is up, and never falls back to sending without it.
public enum EmailSecurity: String, Codable, CaseIterable, Hashable, Sendable {
    /// Plain at first, then upgraded with `STARTTLS`, usually on port 587.
    case startTLS
    /// TLS from the start, usually on port 465.
    case implicitTLS

    public var defaultPort: Int {
        switch self {
        case .startTLS: 587
        case .implicitTLS: 465
        }
    }
}

/// The settings as Hive has them. The password stays in Hive.
public struct EmailSettingsState: Codable, Hashable, Sendable {
    /// Nil until email is set up.
    public let settings: EmailSettings?
    public let hasPassword: Bool

    public init(settings: EmailSettings?, hasPassword: Bool) {
        self.settings = settings
        self.hasPassword = hasPassword
    }
}

/// Sent whole to set up or change email. Changing the host clears the password unless a new one comes
/// with it, and needs confirming, so a stolen session can't send the password somewhere else.
public struct EmailSettingsChange: Codable, Hashable, Sendable {
    public var settings: EmailSettings
    /// A new password, or nil to keep the one already set.
    public var password: String?

    public init(settings: EmailSettings, password: String?) {
        self.settings = settings
        self.password = password
    }
}

// So printing or logging a change can't show its password.
extension EmailSettingsChange: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "EmailSettingsChange(settings: \(settings), password: \(password == nil ? "nil" : "<set>"))"
    }

    public var debugDescription: String {
        description
    }
}

/// What came of sending a test email, which Hive tries once, without retrying.
public enum TestEmailOutcome: Codable, Hashable, Sendable {
    case sent
    /// `serverReply` is what the mail server answered, when the problem is something it said.
    case failed(EmailProblem, serverReply: String?)
}

public enum EmailProblem: String, Codable, Hashable, Sendable {
    case notSetUp
    /// A username is set, but no password.
    case noPassword
    /// The host's name didn't resolve, or nothing answered on the port.
    case couldNotConnect
    case timedOut
    /// The server ended the connection partway through.
    case connectionClosed
    /// No TLS connection, such as for a certificate that isn't trusted or isn't for the host.
    case secureConnectionFailed
    /// The server doesn't offer `STARTTLS`, so Hive sends nothing.
    case startTLSUnavailable
    /// The server offers no way of signing in that Hive supports.
    case signInUnavailable
    case signInRefused
    case senderRefused
    case recipientRefused
    case messageRefused
    /// The server answered something Hive couldn't read as SMTP.
    case unexpectedReply
}
