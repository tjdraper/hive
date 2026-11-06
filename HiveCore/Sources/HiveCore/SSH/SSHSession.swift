import Foundation

/// What one connection to a server needs on the Hive Mac: its run folder, holding the server's
/// `known_hosts` line, and an agent holding Hive's key for it. Both are gone once `body` returns.
struct SSHSession {
    let target: SSHTarget
    let directory: SSHRunDirectory
    let tools: SSHTools

    static func with<Value>(
        _ target: SSHTarget,
        tools: SSHTools,
        body: (SSHSession) async throws -> Value
    ) async throws -> Value {
        let directory = try SSHRunDirectory.make()
        defer { directory.remove() }
        try directory.write(knownHosts: KnownHostsFile.contents(for: target), identity: target.key.publicKey.line)

        let agent = try await SSHAgent.start(socket: directory.agentSocket, tools: tools)
        defer { agent.stop() }
        try await agent.add(target.key, comment: target.hostKeyAlias)

        return try await body(SSHSession(target: target, directory: directory, tools: tools))
    }

    func ssh(_ remoteCommand: String) -> ChildProcess {
        ChildProcess(
            executableURL: tools.ssh,
            arguments: SSHCommand.arguments(for: target, in: directory, remoteCommand: remoteCommand),
            environment: SSHTools.environment()
        )
    }
}

/// Runs a command on a server over SSH. Tests stand in for it, since they never run `ssh`.
protocol SSHRunning: Sendable {
    func run(_ remoteCommand: String, on target: SSHTarget) async throws -> ChildProcess.Result
}

struct SSHRunner: SSHRunning {
    var tools = SSHTools()

    func run(_ remoteCommand: String, on target: SSHTarget) async throws -> ChildProcess.Result {
        try await SSHSession.with(target, tools: tools) { session in
            try await session.ssh(remoteCommand).run()
        }
    }
}
