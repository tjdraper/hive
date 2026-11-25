import Foundation
import GRDB

/// What `docker ps` says of a container, which Scout can't ask (§4).
struct ContainerName: Equatable, Sendable {
    let containerID: String
    let name: String?
    let swarmService: String?
    let composeProject: String?
    let composeService: String?
}

/// The `docker ps` Hive runs to name a server's containers, and reading what it prints. The command is
/// a constant: nothing a Scout sends, container IDs included, ever goes into it.
enum ContainerListing {
    static let composeProjectLabel = "com.docker.compose.project"
    /// Far more than a server runs, so a server can't fill the store with names.
    static let largestContainerCount = 1_000

    /// The running containers, one a line: the full ID, its name, then its Swarm service, Compose
    /// project and Compose service, separated by tabs and empty where it has none.
    static var command: String {
        let labels = [DumpCommand.swarmServiceLabel, composeProjectLabel, DumpCommand.composeServiceLabel]
        let format = (["{{.ID}}", "{{.Names}}"] + labels.map { #"{{.Label "\#($0)"}}"# }).joined(separator: #"\t"#)
        return RemoteCommandLine.line(["docker", "ps", "--no-trunc", "--format", format])
    }

    /// Lines that aren't what the command prints are left out, and a name that isn't one Hive keeps,
    /// such as one with a control character, is taken as missing.
    static func names(in output: Data) -> [ContainerName] {
        let lines = (String(bytes: output, encoding: .utf8) ?? "").split(separator: "\n")
        let names = lines.compactMap { line -> ContainerName? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5, MetricsReportCheck.isContainerID(fields[0]) else { return nil }
            func field(_ index: Int) -> String? {
                MetricsReportCheck.isName(fields[index]) ? fields[index] : nil
            }
            // A container linked to others is listed with their names too, after its own.
            let name = fields[1].split(separator: ",").first.map(String.init).flatMap { MetricsReportCheck.isName($0) ? $0 : nil }
            return ContainerName(
                containerID: fields[0], name: name, swarmService: field(2), composeProject: field(3), composeService: field(4)
            )
        }
        return Array(names.prefix(largestContainerCount))
    }
}

extension ContainerName {
    /// Every name Hive keeps for the server's containers, by ID. A container `docker ps` didn't list
    /// is kept without a name.
    static func kept(forServer serverKey: Int64, in database: Database) throws -> [String: ContainerName] {
        let rows = try Row.fetchAll(database, sql: """
        SELECT containerID, name, swarmService, composeProject, composeService FROM containerName WHERE serverKey = ?
        """, arguments: [serverKey])
        var names: [String: ContainerName] = [:]
        for row in rows {
            let name = ContainerName(
                containerID: row["containerID"],
                name: row["name"],
                swarmService: row["swarmService"],
                composeProject: row["composeProject"],
                composeService: row["composeService"]
            )
            names[name.containerID] = name
        }
        return names
    }
}
