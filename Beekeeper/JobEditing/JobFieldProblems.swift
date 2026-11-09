import HiveKit
import SwiftUI

/// What Hive said was wrong with each field of a job it turned down, by the field and, for a
/// directory, database or time, its place in the list.
struct JobFieldProblems {
    private struct Key: Hashable {
        let field: ConfigurationField
        let index: Int?
    }

    private var messages: [Key: String] = [:]

    init() {}

    /// Nil when the error isn't Hive turning the job down.
    init?(_ error: any Error) {
        guard let refused = error as? HiveRequestError, refused.status == 422,
              let refusal = try? JSONDecoder().decode(ConfigurationRefusal.self, from: refused.body)
        else { return nil }
        for problem in refusal.problems {
            messages[Key(field: problem.field, index: problem.index)] = Self.message(for: problem)
        }
    }

    var isEmpty: Bool {
        messages.isEmpty
    }

    subscript(field: ConfigurationField, index: Int? = nil) -> String? {
        messages[Key(field: field, index: index)]
    }

    /// A row's problems, in the order its fields appear.
    func messages(for fields: [ConfigurationField], at index: Int?) -> [String] {
        fields.compactMap { self[$0, index] }
    }

    // The limits named here are Hive's, in `BackupJobDraftCheck` and `DatabaseDraftCheck`. A refusal doesn't carry them.
    private static let messages: [ConfigurationField: String] = [
        .name: "Enter a name of up to 100 characters.",
        .directories: "Add a directory or a database to back up.",
        .directoryPath: "Enter the directory’s full path on the server.",
        .database: "Hive doesn’t know this database any more. Remove it and add it again.",
        .databaseName: "Use up to 64 letters, digits, “_”, “$” and “-”, not starting with “-”.",
        .databaseUser: "Use up to 64 letters, digits, “_”, “$”, “.” and “-”, not starting with “-”.",
        .databaseServiceName: "Use letters, digits, “_”, “.” and “-”, starting with a letter or digit.",
        .databasePassword: "Enter a password of up to 1024 characters, without tabs or line breaks.",
        .times: "Add a time to run.",
        .time: "Choose a time of day.",
        .dailySnapshots: "Choose from 1 to 3650 days.",
        .monthlySnapshots: "Choose from 0 to 1200 months.",
    ]

    private static let duplicateMessages: [ConfigurationField: String] = [
        .name: "Another job on this server has this name.",
        .databaseName: "Another database in this job has this name.",
        .time: "This time is already in the list.",
    ]

    private static func message(for problem: ConfigurationProblem) -> String {
        if problem.field == .directoryFolder { return folderMessage(for: problem.reason) }
        if problem.field == .directoryPath, problem.reason == .notAbsolute { return "The path on the server has to start with “/”." }
        if problem.reason == .duplicate, let message = duplicateMessages[problem.field] { return message }
        return messages[problem.field] ?? "Hive turned this down."
    }

    private static func folderMessage(for reason: ConfigurationProblemReason) -> String {
        switch reason {
        case .notRelative: "The folder in the snapshot can’t start with “/”."
        case .emptyPart: "The folder has an empty part, such as “images//galleries” or a “/” at the end."
        case .dotPart: "The folder can’t have a “.” or “..” part."
        case .duplicate: "Another directory goes in this folder."
        case .insideAnother: "This folder is inside another of the job’s folders, whose backup would delete it."
        default: "Enter a folder name, with parts of up to 255 characters."
        }
    }
}

/// Hive's reasons for turning a field down, shown under it.
struct FieldProblemText: View {
    let messages: [String]

    init(_ messages: [String]) {
        self.messages = messages
    }

    init(_ message: String?) {
        messages = message.map { [$0] } ?? []
    }

    var body: some View {
        ForEach(messages, id: \.self) { message in
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
