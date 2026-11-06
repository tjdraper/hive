import Foundation
import HiveKit

/// Where rsync reads a directory from.
enum RsyncOrigin: Sendable {
    case server(SSHTarget)
    /// A folder on this Mac. Tests use it, since they never run `ssh`.
    case thisMac
}

/// Runs Hive's bundled rsync, over `ssh` built by `SSHCommand` when it reads from a server.
struct RsyncRunner: Sendable {
    /// Beside the daemon in Hive.app, which only root can change (§4).
    let rsync: URL
    var sshTools = SSHTools()

    /// Lists the top of `path` on the origin.
    func list(_ path: String, from origin: RsyncOrigin) async throws -> ChildProcess.Result {
        try await run(RsyncCommand.list(), path: path, destination: nil, from: origin)
    }

    func pull(
        _ path: String,
        from origin: RsyncOrigin,
        into destination: URL,
        linkingTo previous: URL?
    ) async throws -> ChildProcess.Result {
        try await run(RsyncCommand.pull(linkingTo: previous), path: path, destination: destination, from: origin)
    }

    private func run(_ options: [String], path: String, destination: URL?, from origin: RsyncOrigin) async throws -> ChildProcess.Result {
        let destination = destination.map { [RsyncCommand.contentsPath($0.fileSystemPath)] } ?? []
        switch origin {
        case .thisMac:
            return try await process(options + [RsyncCommand.contentsPath(path)] + destination).run()
        case .server(let target):
            // A session for each run of rsync, since the agent drops Hive's key two minutes after it
            // starts, and a long transfer before this one could outlast that.
            return try await SSHSession.with(target, tools: sshTools) { session in
                let source = RsyncCommand.remoteSource(host: target.connection.host, path: path)
                return try await process(options + ["-e", session.remoteShell(), source] + destination).run()
            }
        }
    }

    private func process(_ arguments: [String]) -> ChildProcess {
        ChildProcess(executableURL: rsync, arguments: arguments, environment: SSHTools.environment())
    }
}
