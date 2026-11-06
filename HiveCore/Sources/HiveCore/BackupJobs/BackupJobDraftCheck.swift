import Foundation
import HiveKit

/// The checks a job passes before it's saved, other than its name being free on its server and its
/// databases' IDs being ones it already has.
enum BackupJobDraftCheck {
    static let dailySnapshots = 1 ... 3650
    static let monthlySnapshots = 0 ... 1200

    /// The draft as it's stored, with its times in order, or every problem with it.
    static func validated(_ draft: BackupJobDraft) throws -> BackupJobDraft {
        var problems: [ConfigurationProblem] = []

        let name = DisplayName.validated(draft.name)
        if name == nil { problems.append(ConfigurationProblem(field: .name, reason: .invalid)) }
        if draft.directories.isEmpty, draft.databases.isEmpty {
            problems.append(ConfigurationProblem(field: .directories, reason: .nothingToBackUp))
        }

        let directories = draft.directories.map { BackupDirectory(path: ServerPath.trimmed($0.path), folder: $0.folder) }
        problems += ServerPath.problems(in: directories.map(\.path))
        problems += SnapshotFolder.problems(in: directories.map(\.folder))
        problems += DatabaseDraftCheck.problems(in: draft.databases)
        problems += timeProblems(in: draft.times)
        if !dailySnapshots.contains(draft.retention.dailySnapshots) {
            problems.append(ConfigurationProblem(field: .dailySnapshots, reason: .outOfRange))
        }
        if !monthlySnapshots.contains(draft.retention.monthlySnapshots) {
            problems.append(ConfigurationProblem(field: .monthlySnapshots, reason: .outOfRange))
        }

        guard let name, problems.isEmpty else { throw ConfigurationChangeError.refused(problems) }
        return BackupJobDraft(
            name: name,
            directories: directories,
            databases: draft.databases,
            times: draft.times.sorted(),
            retention: draft.retention
        )
    }

    private static func timeProblems(in times: [TimeOfDay]) -> [ConfigurationProblem] {
        guard !times.isEmpty else { return [ConfigurationProblem(field: .times, reason: .missing)] }
        var problems: [ConfigurationProblem] = []
        var seen: Set<TimeOfDay> = []
        for (index, time) in times.enumerated() {
            if !(0 ..< 24).contains(time.hour) || !(0 ..< 60).contains(time.minute) {
                problems.append(ConfigurationProblem(field: .time, index: index, reason: .outOfRange))
            } else if !seen.insert(time).inserted {
                problems.append(ConfigurationProblem(field: .time, index: index, reason: .duplicate))
            }
        }
        return problems
    }
}

/// A directory's path on the server.
enum ServerPath {
    /// Linux's `PATH_MAX`.
    static let longest = 4096

    /// Without trailing slashes, which mean nothing here, so the same directory is always written the same way.
    static func trimmed(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func problems(in paths: [String]) -> [ConfigurationProblem] {
        paths.enumerated().compactMap { index, path in
            if path.isEmpty || path.utf8.count > longest || TextCheck.hasControlCharacters(path) {
                ConfigurationProblem(field: .directoryPath, index: index, reason: .invalid)
            } else if !path.hasPrefix("/") {
                ConfigurationProblem(field: .directoryPath, index: index, reason: .notAbsolute)
            } else {
                nil
            }
        }
    }
}

/// Where a directory goes within each snapshot. Every folder has to stay inside the snapshot, and none
/// can be inside another, since backing up the outer one would delete what the inner one put there.
enum SnapshotFolder {
    /// The longest file name APFS allows, in UTF-8 bytes.
    static let longestPart = 255
    static let longest = 1024

    static func problems(in folders: [String]) -> [ConfigurationProblem] {
        var problems: [ConfigurationProblem] = []
        var valid: [(index: Int, parts: [Substring])] = []
        for (index, folder) in folders.enumerated() {
            if let reason = problem(with: folder) {
                problems.append(ConfigurationProblem(field: .directoryFolder, index: index, reason: reason))
            } else {
                valid.append((index, folder.split(separator: "/", omittingEmptySubsequences: false)))
            }
        }

        for (position, folder) in valid.enumerated() {
            let earlier = valid[..<position]
            if earlier.contains(where: { $0.parts == folder.parts }) {
                problems.append(ConfigurationProblem(field: .directoryFolder, index: folder.index, reason: .duplicate))
            } else if valid.contains(where: { $0.parts.count < folder.parts.count && folder.parts.starts(with: $0.parts) }) {
                problems.append(ConfigurationProblem(field: .directoryFolder, index: folder.index, reason: .insideAnother))
            }
        }
        return problems.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
    }

    private static func problem(with folder: String) -> ConfigurationProblemReason? {
        if folder.isEmpty || folder.utf8.count > longest || TextCheck.hasControlCharacters(folder) { return .invalid }
        if folder.hasPrefix("/") { return .notRelative }
        let parts = folder.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: \.isEmpty) { return .emptyPart }
        if parts.contains(where: { $0 == "." || $0 == ".." }) { return .dotPart }
        if parts.contains(where: { $0.utf8.count > longestPart }) { return .invalid }
        return nil
    }
}
