import Foundation
import HiveKit
import os

/// Sends a message Hive writes on its own, such as an alert, trying again with a growing delay while
/// the provider is unreachable or answers "not now". Each try reads the settings again, so a fix made
/// meanwhile is picked up.
struct EmailDelivery: Sendable {
    enum Outcome: Equatable {
        case sent
        /// A problem trying again won't fix, such as a refused password. Nil when Hive couldn't read its
        /// own settings or open the password.
        case failed(EmailProblem?)
        /// Still failing once `giveUpAfter` had passed.
        case gaveUp(EmailProblem)
    }

    static let firstDelay: TimeInterval = 60
    static let longestDelay: TimeInterval = 60 * 60
    /// Long enough to outlast a provider's outage. An alert still true after that is sent again (§13).
    static let giveUpAfter: TimeInterval = 24 * 60 * 60

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Email")

    let sender: EmailSender
    let pause: @Sendable (Duration) async throws -> Void
    let now: @Sendable () -> Date

    /// The delay before the try after `failures` failed ones.
    static func delay(afterFailures failures: Int) -> TimeInterval {
        min(firstDelay * pow(2, Double(max(failures - 1, 0))), longestDelay)
    }

    func deliver(_ message: EmailMessage) async -> Outcome {
        let started = now()
        var failures = 0
        while true {
            let failure: EmailSendFailure
            do {
                try await sender.send(message)
                return .sent
            } catch let sendFailure as EmailSendFailure {
                failure = sendFailure
            } catch {
                Self.logger.error("Couldn't send an email: \(String(describing: type(of: error)), privacy: .public)")
                return .failed(nil)
            }
            guard failure.isTransient else { return .failed(failure.problem) }

            failures += 1
            let delay = Self.delay(afterFailures: failures)
            guard now().timeIntervalSince(started) + delay <= Self.giveUpAfter else {
                Self.logger.error("Gave up sending an email after \(failures, privacy: .public) tries")
                return .gaveUp(failure.problem)
            }
            Self.logger.notice("Trying the email again in \(Int(delay), privacy: .public)s")
            do {
                try await pause(.seconds(delay))
            } catch {
                return .gaveUp(failure.problem)
            }
        }
    }
}
