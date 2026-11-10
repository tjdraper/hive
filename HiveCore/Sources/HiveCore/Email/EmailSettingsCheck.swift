import Foundation
import HiveKit

/// The checks email settings pass before they're saved. Every value ends up in an SMTP command or a
/// message header, where a line break would let it add commands or headers of its own.
enum EmailSettingsCheck {
    static let ports = 1 ... 65535
    /// The longest a DNS name can be.
    static let longestHost = 253
    /// The longest RFC 5321 allows in `MAIL FROM` and `RCPT TO`.
    static let longestAddress = 254
    static let longestUsername = 256
    static let longestPassword = 1024
    /// Alerts go to a few people, and a provider limits recipients per message anyway.
    static let mostRecipients = 20

    /// The settings as they're stored, trimmed and with the host in lowercase, or every problem with them.
    /// `keepsPassword` says whether a password is already set that the change would keep, given its host.
    static func validated(_ change: EmailSettingsChange, keepsPassword: (String) -> Bool) throws -> EmailSettings {
        let requested = change.settings
        var problems: [ConfigurationProblem] = []

        let host = requested.host.trimmingCharacters(in: .whitespaces).lowercased()
        if !isHostName(host) { problems.append(ConfigurationProblem(field: .host, reason: .invalid)) }

        if !ports.contains(requested.port) { problems.append(ConfigurationProblem(field: .port, reason: .outOfRange)) }

        let username = requested.username.trimmingCharacters(in: .whitespaces)
        if username.utf8.count > longestUsername || TextCheck.hasControlCharacters(username) {
            problems.append(ConfigurationProblem(field: .user, reason: .invalid))
        }

        if let problem = passwordProblem(change.password, username: username, keepsPassword: keepsPassword(host)) {
            problems.append(problem)
        }

        let sender = requested.senderAddress.trimmingCharacters(in: .whitespaces)
        if !isAddress(sender) { problems.append(ConfigurationProblem(field: .senderAddress, reason: .invalid)) }

        let (recipients, recipientProblems) = checkedRecipients(requested.recipients)
        problems += recipientProblems

        guard problems.isEmpty else { throw ConfigurationChangeError.refused(problems) }
        return EmailSettings(
            host: host,
            port: requested.port,
            security: requested.security,
            username: username,
            senderAddress: sender,
            recipients: recipients
        )
    }

    private static func passwordProblem(_ password: String?, username: String, keepsPassword: Bool) -> ConfigurationProblem? {
        if let password {
            // A NUL would end the password early in `AUTH PLAIN`.
            let isValid = !password.isEmpty && password.utf8.count <= longestPassword && !TextCheck.hasControlCharacters(password)
            return isValid ? nil : ConfigurationProblem(field: .password, reason: .invalid)
        }
        return !username.isEmpty && !keepsPassword ? ConfigurationProblem(field: .password, reason: .missing) : nil
    }

    /// The recipients trimmed, and a problem for each that isn't an address or repeats one before it.
    private static func checkedRecipients(_ requested: [String]) -> ([String], [ConfigurationProblem]) {
        var recipients: [String] = []
        var problems: [ConfigurationProblem] = []
        for (index, requestedRecipient) in requested.enumerated() {
            let recipient = requestedRecipient.trimmingCharacters(in: .whitespaces)
            if !isAddress(recipient) {
                problems.append(ConfigurationProblem(field: .recipient, index: index, reason: .invalid))
            } else if recipients.contains(where: { $0.caseInsensitiveCompare(recipient) == .orderedSame }) {
                problems.append(ConfigurationProblem(field: .recipient, index: index, reason: .duplicate))
            } else {
                recipients.append(recipient)
            }
        }
        if requested.isEmpty {
            problems.append(ConfigurationProblem(field: .recipients, reason: .missing))
        } else if requested.count > mostRecipients {
            problems.append(ConfigurationProblem(field: .recipients, reason: .outOfRange))
        }
        return (recipients, problems)
    }

    /// A DNS name and not an address: TLS checks the certificate against the name, and NIOSSL won't
    /// check one against an address.
    static func isHostName(_ host: String) -> Bool {
        guard TextCheck.isPlainName(host, extra: "-.", longest: longestHost), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return false
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4 = labels.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        return !isIPv4 && labels.allSatisfy { !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }
    }

    /// A plain ASCII address with one `@`. Quoted local parts, address literals and non-ASCII addresses,
    /// which need `SMTPUTF8`, are left out: nobody's alert address needs them.
    static func isAddress(_ address: String) -> Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard address.utf8.count <= longestAddress, parts.count == 2, !parts[0].isEmpty, parts[0].utf8.count <= 64 else { return false }
        let localAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-/=?^_`{|}~.")
        let local = String(parts[0])
        return local.unicodeScalars.allSatisfy(localAllowed.contains)
            && !local.hasPrefix(".") && !local.hasSuffix(".") && !local.contains("..")
            && isHostName(String(parts[1]).lowercased())
    }
}
