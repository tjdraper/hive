import Foundation
import HiveKit
import os

/// Sends one message with the email settings as they're stored now, trying once.
struct EmailSender: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Email")

    let store: EmailSettingsStore
    let settings: HiveSettingsStore
    let sealer: SecretSealer
    let connector: any SMTPConnecting
    /// For the message's date.
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(
        database: HiveDatabase,
        settings: HiveSettingsStore,
        sealer: SecretSealer,
        connector: any SMTPConnecting,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date
    ) {
        store = EmailSettingsStore(database: database)
        self.settings = settings
        self.sealer = sealer
        self.connector = connector
        self.calendar = calendar
        self.now = now
    }

    /// Throws `EmailSendFailure`.
    func send(_ message: EmailMessage) async throws {
        guard let stored = try store.stored() else { throw EmailSendFailure(.notSetUp) }
        let email = stored.settings
        var credentials: SMTPCredentials?
        if !email.username.isEmpty {
            guard let sealedPassword = stored.sealedPassword else { throw EmailSendFailure(.noPassword) }
            guard let password = String(bytes: try sealer.open(sealedPassword), encoding: .utf8) else {
                throw EmailSendFailure(.noPassword)
            }
            credentials = SMTPCredentials(username: email.username, password: password)
        }

        let built = EmailMessageBuilder(
            senderName: try settings.settings().name,
            senderAddress: email.senderAddress,
            recipients: email.recipients,
            date: now(),
            timeZone: calendar.timeZone,
            messageID: UUID()
        ).build(message)

        let started = ContinuousClock.now
        do {
            try await connector.withConnection(to: SMTPServer(host: email.host, port: email.port, security: email.security)) { transport in
                try await SMTPConversation(transport: transport, security: email.security, credentials: credentials)
                    .send(built, from: email.senderAddress, to: email.recipients)
            }
        } catch let failure as EmailSendFailure {
            let code = failure.reply.map { String($0.code) } ?? "none"
            Self.logger.error(
                "Couldn't send an email: \(failure.problem.rawValue, privacy: .public), reply \(code, privacy: .public)"
            )
            throw failure
        }
        let seconds = (ContinuousClock.now - started).roundedSeconds
        Self.logger.notice("Sent an email to \(email.recipients.count, privacy: .public) recipients in \(seconds, privacy: .public)s")
    }
}
