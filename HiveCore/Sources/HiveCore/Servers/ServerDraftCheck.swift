import Foundation
import HiveKit

/// The checks a server passes before it's saved, other than its name being free.
enum ServerDraftCheck {
    static let ports = 1 ... 65535
    /// The longest a DNS name can be.
    static let longestHost = 253
    static let longestUser = 64

    /// The draft as it's stored, trimmed and with its host in lowercase, or every problem with it.
    static func validated(_ draft: ServerDraft) throws -> ServerDraft {
        var problems: [ConfigurationProblem] = []

        let name = DisplayName.validated(draft.name)
        if name == nil { problems.append(ConfigurationProblem(field: .name, reason: .invalid)) }

        var connection: ServerConnection?
        if let requested = draft.connection {
            let host = requested.host.trimmingCharacters(in: .whitespaces).lowercased()
            // IPv6 addresses need the colon. `ssh` takes them without brackets.
            if !TextCheck.isPlainName(host, extra: "-._:", longest: longestHost) {
                problems.append(ConfigurationProblem(field: .host, reason: .invalid))
            }

            if !ports.contains(requested.port) {
                problems.append(ConfigurationProblem(field: .port, reason: .outOfRange))
            }

            let user = requested.user.trimmingCharacters(in: .whitespaces)
            if !TextCheck.isPlainName(user, extra: "-._", longest: longestUser) {
                problems.append(ConfigurationProblem(field: .user, reason: .invalid))
            }
            connection = ServerConnection(host: host, port: requested.port, user: user)
        }

        if let quota = draft.quotaBytes, quota <= 0 {
            problems.append(ConfigurationProblem(field: .quota, reason: .outOfRange))
        }

        guard let name, problems.isEmpty else { throw ConfigurationChangeError.refused(problems) }
        return ServerDraft(name: name, connection: connection, quotaBytes: draft.quotaBytes)
    }
}
