import Foundation
import HiveKit
import os

/// Sends the emails alerts owe, one at a time and oldest first, so a condition's end never arrives
/// before its start.
actor AlertMailer {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Alerts")

    private let store: AlertStore
    private let messages: AlertMessageBuilder
    private let delivery: EmailDelivery
    private let now: @Sendable () -> Date
    private var sending: Task<Void, Never>?

    init(store: AlertStore, messages: AlertMessageBuilder, delivery: EmailDelivery, now: @escaping @Sendable () -> Date) {
        self.store = store
        self.messages = messages
        self.delivery = delivery
        self.now = now
    }

    /// Starts sending what's owed, unless it already is. Anything owed meanwhile is sent before it stops.
    func sendOwed() {
        guard sending == nil else { return }
        sending = Task { await drain() }
    }

    func waitUntilIdle() async {
        while let sending {
            await sending.value
        }
    }

    /// An email being tried stays owed, for the next start to send.
    func stop() async {
        sending?.cancel()
        await waitUntilIdle()
    }

    private func drain() async {
        defer { sending = nil }
        while !Task.isCancelled {
            do {
                guard let alert = try store.nextOwed() else { return }
                try store.startEmail(for: alert, at: now())
                let message: EmailMessage
                do {
                    message = try messages.message(for: alert)
                } catch {
                    // Left owed, it would hold up every alert after it.
                    Self.logger.error("Couldn't write an alert's email: \(alert.facts.kind, privacy: .public)")
                    try store.finishEmail(for: alert)
                    continue
                }
                let outcome = await delivery.deliver(message)
                guard !Task.isCancelled else { return }
                try store.finishEmail(for: alert)
                log(outcome, for: alert)
            } catch {
                // Trying again now would fail the same way. What's owed goes after the next check.
                Self.logger.error("Couldn't send an alert: \(String(describing: type(of: error)), privacy: .public)")
                return
            }
        }
    }

    private func log(_ outcome: EmailDelivery.Outcome, for alert: AlertRecord) {
        let kind = alert.facts.kind
        let email = alert.emailOwed?.rawValue ?? "none"
        switch outcome {
        case .sent:
            Self.logger.notice("Emailed an alert: \(kind, privacy: .public), \(email, privacy: .public)")
        case .failed(let problem):
            let reason = problem?.rawValue ?? "unreadable settings"
            Self.logger.error("Couldn't email an alert: \(kind, privacy: .public), \(email, privacy: .public): \(reason, privacy: .public)")
        case .gaveUp(let problem):
            let reason = problem.rawValue
            Self.logger.error("Gave up on an alert: \(kind, privacy: .public), \(email, privacy: .public): \(reason, privacy: .public)")
        }
    }
}
