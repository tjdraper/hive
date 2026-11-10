import Foundation
import HiveKit

/// The email settings as they're being edited, with the recipients as typed.
struct EmailDraft: Equatable {
    var host: String
    var port: Int
    var security: EmailSecurity
    var username: String
    var senderAddress: String
    /// One address per line, or separated by commas.
    var recipients: String
    /// Nil, or empty, keeps the password Hive has.
    var newPassword: String?

    init(_ settings: EmailSettings?) {
        host = settings?.host ?? ""
        port = settings?.port ?? EmailSecurity.startTLS.defaultPort
        security = settings?.security ?? .startTLS
        username = settings?.username ?? ""
        senderAddress = settings?.senderAddress ?? ""
        recipients = settings?.recipients.joined(separator: "\n") ?? ""
        newPassword = nil
    }

    var recipientList: [String] {
        recipients
            .split { $0 == "," || $0 == ";" || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var settings: EmailSettings {
        EmailSettings(
            host: host,
            port: port,
            security: security,
            username: username,
            senderAddress: senderAddress,
            recipients: recipientList
        )
    }

    var change: EmailSettingsChange {
        EmailSettingsChange(settings: settings, password: newPassword.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Hive checks the rest, and says which field it turned down.
    var isComplete: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !senderAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && !recipientList.isEmpty
    }

    /// Whether Hive will clear the password it has, which a new host does.
    func changesHost(from saved: EmailSettings?) -> Bool {
        guard let saved else { return false }
        return host.trimmingCharacters(in: .whitespaces).lowercased() != saved.host
    }

    /// Picks the usual port for the security chosen, unless another port was typed.
    mutating func choose(_ newSecurity: EmailSecurity) {
        if port == security.defaultPort { port = newSecurity.defaultPort }
        security = newSecurity
    }
}

/// What Hive said was wrong with each field of email settings it turned down.
struct EmailFieldProblems {
    private var messages: [ConfigurationField: [String]] = [:]

    init() {}

    /// Nil when the error isn't Hive turning the settings down. `recipients` are the ones sent, which a
    /// recipient's problem names by its place.
    init?(_ error: any Error, recipients: [String]) {
        guard let refused = error as? HiveRequestError, refused.status == 422,
              let refusal = try? JSONDecoder().decode(ConfigurationRefusal.self, from: refused.body)
        else { return nil }
        for problem in refusal.problems {
            let field: ConfigurationField = problem.field == .recipient ? .recipients : problem.field
            let recipient = problem.index.flatMap { recipients.indices.contains($0) ? recipients[$0] : nil }
            messages[field, default: []].append(Self.message(for: problem, recipient: recipient))
        }
    }

    subscript(field: ConfigurationField) -> [String] {
        messages[field] ?? []
    }

    // The limits named here are Hive's, in `EmailSettingsCheck`. A refusal doesn't carry them.
    private static let fieldMessages: [ConfigurationField: String] = [
        .host: "Enter the mail server's name, such as smtp.example.com. Hive checks its certificate against the name, "
            + "so an address won't do.",
        .port: "Choose a port from 1 to 65535.",
        .user: "Enter a username of up to 256 characters, without tabs or line breaks.",
        .password: "Enter a password of up to 1024 characters, without tabs or line breaks.",
        .senderAddress: "Enter an email address, such as hive@example.com.",
        .recipients: "Enter at least one address to send to.",
    ]

    private static func message(for problem: ConfigurationProblem, recipient: String?) -> String {
        switch (problem.field, problem.reason) {
        case (.recipient, .duplicate): "“\(recipient ?? "")” is in the list twice."
        case (.recipient, _): "“\(recipient ?? "")” isn't an email address."
        case (.recipients, .outOfRange): "Enter up to 20 addresses."
        case (.password, .missing): "Enter the password."
        default: fieldMessages[problem.field] ?? "Hive turned this down."
        }
    }
}
