import Foundation

/// Runs `DumpCommand`'s commands on the server over `ssh`, or for tests, with `/bin/sh` on this Mac.
struct DatabaseDumpRunner: Sendable {
    var sshTools = SSHTools()
    /// Where commands run on this Mac find `docker` and the dump tools, which tests stand in for with scripts.
    var localSearchPath = "/usr/bin:/bin"

    /// `output`, when given, takes standard output as it arrives instead of it being collected.
    func run(
        _ command: String,
        input: Data? = nil,
        from origin: BackupOrigin,
        output: (@Sendable (Data) throws -> Void)? = nil
    ) async throws -> ChildProcess.Result {
        var process: ChildProcess
        switch origin {
        case .thisMac:
            process = ChildProcess(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", command],
                environment: SSHTools.environment(adding: ["PATH": localSearchPath])
            )
        case .server(let target):
            return try await SSHSession.with(target, tools: sshTools) { session in
                var process = session.ssh(command)
                process.input = input
                process.standardOutputHandler = output
                return try await process.run()
            }
        }
        process.input = input
        process.standardOutputHandler = output
        return try await process.run()
    }
}
