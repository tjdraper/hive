import Foundation
import HiveKit
import os

/// Setting up, changing and turning off email, and sending a test email. The password is sealed
/// before anything is stored.
struct EmailSettingsWorkflow: Sendable {
    /// Beekeeper gives up on a request after a minute without an answer, and would take the Hive for offline.
    static let testEmailTimeout = Duration.seconds(45)

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Email")

    let sender: EmailSender
    let now: @Sendable () -> Date

    private var store: EmailSettingsStore {
        sender.store
    }

    func state() throws -> EmailSettingsState {
        try store.state()
    }

    func change(_ change: EmailSettingsChange, isConfirmed: Bool, by deviceID: UUID) throws -> EmailSettingsState {
        let current = try store.stored()
        let settings = try EmailSettingsCheck.validated(change) { host in
            current?.sealedPassword != nil && current?.settings.host == host
        }
        let newPassword = try change.password.map { try sender.sealer.seal(Data($0.utf8)) }
        let (old, new) = try store.save(settings, newPassword: newPassword, isConfirmed: isConfirmed, by: deviceID, at: now())

        let changes = EmailSettingsStore.changes(from: old, to: settings, passwordEntered: newPassword != nil)
        if !changes.isEmpty {
            let reasons = ConfirmationRequirement.logged(ConfirmationRequirement.reasons(from: old, to: settings))
            Self.logger.notice(
                "Changed the email settings (\(changes.count, privacy: .public) changes, confirmed: \(reasons, privacy: .public))"
            )
        }
        return new
    }

    func turnOff(by deviceID: UUID) throws -> Bool {
        guard try store.turnOff(by: deviceID, at: now()) else { return false }
        Self.logger.notice("Turned email off")
        return true
    }

    /// Tries once, so the person hears straight away what went wrong.
    func sendTest() async throws -> TestEmailOutcome {
        let hiveName = try sender.settings.settings().name
        let message = EmailMessage(
            subject: "Test email from “\(hiveName)”",
            body: """
            This is a test email from the Hive “\(hiveName)”. Its email is working, and it will send alerts \
            here when something goes wrong with its backups.
            """
        )
        do {
            try await withThrowingTaskGroup { group in
                group.addTask { try await sender.send(message) }
                group.addTask {
                    try await Task.sleep(for: Self.testEmailTimeout)
                    throw EmailSendFailure(.timedOut)
                }
                try await group.next()
                group.cancelAll()
            }
            return .sent
        } catch let failure as EmailSendFailure {
            return .failed(failure.problem, serverReply: failure.reply?.text)
        }
    }
}
