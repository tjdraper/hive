import Foundation

enum ContainerMatch: Equatable {
    case found(id: String)
    case notFound
    case notUnique
}

/// Finds a database's container in `docker ps`'s output from `DumpCommand.containerList()`. A name has
/// to equal a container's Swarm or Compose service name, never just appear within it, so `site_db`
/// can't pick up `site_db_old` or `othersite_db` (§11).
enum ContainerListReader {
    static func match(serviceName: String, in output: Data) -> ContainerMatch {
        let lines = (String(bytes: output, encoding: .utf8) ?? "").split(separator: "\n")
        let matches = lines.compactMap { line -> String? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, isContainerID(fields[0]) else { return nil }
            return fields[1] == serviceName || fields[2] == serviceName ? fields[0] : nil
        }
        switch matches.count {
        case 0: return .notFound
        case 1: return .found(id: matches[0])
        default: return .notUnique
        }
    }

    /// `--no-trunc` gives the full 64 hexadecimal digits.
    private static func isContainerID(_ text: String) -> Bool {
        text.utf8.count == 64 && text.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }
}
