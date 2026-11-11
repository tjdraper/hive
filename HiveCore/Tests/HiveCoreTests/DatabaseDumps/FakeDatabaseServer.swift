import Foundation
@testable import HiveCore

/// Stands in for a server's `docker` and dump tools with scripts, which record what they were run with
/// and answer as they're told. `docker exec` runs its command on this Mac, finding the other scripts.
final class FakeDatabaseServer {
    static let dumpTools = ["mariadb-dump", "mysqldump", "pg_dump"]

    private let temporary: TemporaryDirectory
    private let tools: URL
    private let record: URL

    init() throws {
        temporary = try TemporaryDirectory()
        tools = temporary.url.appending(path: "tools", directoryHint: .isDirectory)
        record = temporary.url.appending(path: "record", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
        for tool in ["docker"] + Self.dumpTools {
            try install(tool)
        }
        setContainers([])
        answer(output: Data())
    }

    /// For `DatabaseDumpRunner`, ahead of the Mac's own tools.
    var searchPath: String {
        tools.fileSystemPath + ":/usr/bin:/bin"
    }

    func remove(_ tool: String) throws {
        try FileManager.default.removeItem(at: tools.appending(path: tool))
    }

    /// What `docker ps` prints.
    func setContainers(_ lines: [String]) {
        write(lines.map { $0 + "\n" }.joined(), to: "containers")
    }

    /// What the dump tools write and exit with.
    func answer(output: Data, error: String = "", status: Int32 = 0, tools: [String] = dumpTools) {
        for tool in tools {
            try? output.write(to: record.appending(path: "\(tool).output"))
            write(error, to: "\(tool).error")
            write(String(status), to: "\(tool).status")
        }
    }

    /// Dump tools wait, as a slow dump would, until `release()`.
    func hold() {
        write("", to: "hold")
    }

    func release() {
        try? FileManager.default.removeItem(at: record.appending(path: "hold"))
    }

    /// Each time `docker` or a dump tool ran: its name, then its arguments.
    var runs: [String] {
        recorded("arguments")?.split(separator: "\n").map(String.init) ?? []
    }

    /// The option file a MySQL dump tool read its user and password from.
    var optionFile: String? {
        recorded("option-file")
    }

    /// `PGPASSWORD` as pg_dump saw it.
    var postgresPassword: String? {
        recorded("postgres-password")
    }

    private func recorded(_ name: String) -> String? {
        try? String(contentsOf: record.appending(path: name), encoding: .utf8)
    }

    private func write(_ text: String, to name: String) {
        try? Data(text.utf8).write(to: record.appending(path: name))
    }

    private func install(_ tool: String) throws {
        let record = RemoteCommandLine.quoted(record.fileSystemPath)
        let script = tool == "docker" ? """
        #!/bin/sh
        printf 'docker %s\\n' "$*" >> \(record)/arguments
        case "$1" in
        ps) cat \(record)/containers; exit 0 ;;
        exec) shift; [ "$1" = --interactive ] || exit 125; shift 2; exec "$@" ;;
        esac
        exit 125
        """ : """
        #!/bin/sh
        tool=$(basename "$0")
        printf '%s %s\\n' "$tool" "$*" >> \(record)/arguments
        for argument in "$@"; do
            case "$argument" in
            --defaults-extra-file=*) cat "${argument#--defaults-extra-file=}" > \(record)/option-file ;;
            esac
        done
        if [ -n "${PGPASSWORD+set}" ]; then printf '%s' "$PGPASSWORD" > \(record)/postgres-password; fi
        while [ -e \(record)/hold ]; do sleep 0.05; done
        cat \(record)/"$tool.output"
        cat \(record)/"$tool.error" >&2
        exit "$(cat \(record)/"$tool.status")"
        """
        let url = tools.appending(path: tool)
        try Data((script + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.fileSystemPath)
    }
}

/// What `docker ps` prints for a container, as `DumpCommand.containerList()` asks.
func containerLine(id: Character = "a", swarmService: String = "", composeService: String = "") -> String {
    "\(String(repeating: id, count: 64))\t\(swarmService)\t\(composeService)"
}

func gunzip(_ url: URL) throws -> Data {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/gzip")
    process.arguments = ["-dc", url.fileSystemPath]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    return data
}
