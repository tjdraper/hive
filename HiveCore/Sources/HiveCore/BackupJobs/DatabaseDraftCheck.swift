import Foundation
import HiveKit

/// The checks on a job's databases that need nothing but the draft. Names and users go into dump
/// commands, and a database's name also names its dump, so they're kept to plain characters.
enum DatabaseDraftCheck {
    /// MySQL's limit for both. Postgres's is a little lower and it refuses longer ones itself.
    static let longestName = 64
    static let longestServiceName = 255
    static let longestPassword = 1024

    static func problems(in databases: [BackupDatabaseDraft]) -> [ConfigurationProblem] {
        var problems: [ConfigurationProblem] = []
        var ids: Set<UUID> = []
        var names: Set<String> = []
        for (index, database) in databases.enumerated() {
            if let id = database.id, !ids.insert(id).inserted {
                problems.append(ConfigurationProblem(field: .database, index: index, reason: .duplicate))
            }
            let settings = database.settings
            if !TextCheck.isPlainName(settings.name, extra: "_$-", longest: longestName) {
                problems.append(ConfigurationProblem(field: .databaseName, index: index, reason: .invalid))
            } else if !names.insert(settings.name).inserted {
                problems.append(ConfigurationProblem(field: .databaseName, index: index, reason: .duplicate))
            }
            if !TextCheck.isPlainName(settings.user, extra: "_$.-", longest: longestName) {
                problems.append(ConfigurationProblem(field: .databaseUser, index: index, reason: .invalid))
            }
            if case .container(let serviceName) = settings.location, !isServiceName(serviceName) {
                problems.append(ConfigurationProblem(field: .databaseServiceName, index: index, reason: .invalid))
            }
            if let password = database.password, !isPassword(password) {
                problems.append(ConfigurationProblem(field: .databasePassword, index: index, reason: .invalid))
            }
        }
        return problems
    }

    /// Docker's rule for names: a letter or digit, then letters, digits, `_`, `.` and `-`.
    private static func isServiceName(_ name: String) -> Bool {
        TextCheck.isPlainName(name, extra: "_.-", longest: longestServiceName)
            && !name.hasPrefix("_") && !name.hasPrefix(".")
    }

    private static func isPassword(_ password: String) -> Bool {
        !password.isEmpty && password.utf8.count <= longestPassword && !TextCheck.hasControlCharacters(password)
    }
}
