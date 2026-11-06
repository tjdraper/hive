import Darwin
import Foundation

enum SSHAgentError: Error, Equatable {
    case didNotStart
    case couldNotAddKey(status: Int32)
}

/// An `ssh-agent` of Hive's own, holding one key for one connection. The key reaches it through
/// `ssh-add`'s standard input, so it's never written to disk, and `ssh` can use it but not read it.
final class SSHAgent {
    /// `ssh` only needs the key while it signs in. Should Hive end without stopping the agent, the key
    /// leaves the agent on its own after this.
    static let keyLifetimeSeconds = 120
    private static let startTimeout: Duration = .seconds(5)
    private static let pollInterval: Duration = .milliseconds(10)

    private let process: Process
    let socket: URL
    private let tools: SSHTools

    private init(process: Process, socket: URL, tools: SSHTools) {
        self.process = process
        self.socket = socket
        self.tools = tools
    }

    /// Returns once the agent is listening on `socket`.
    static func start(socket: URL, tools: SSHTools) async throws -> SSHAgent {
        let process = Process()
        process.executableURL = tools.agent
        process.arguments = ["-D", "-a", socket.fileSystemPath]
        process.environment = SSHTools.environment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let agent = SSHAgent(process: process, socket: socket, tools: tools)

        let deadline = ContinuousClock.now + startTimeout
        while !isSocket(socket) {
            guard process.isRunning, ContinuousClock.now < deadline else {
                agent.stop()
                throw SSHAgentError.didNotStart
            }
            try await Task.sleep(for: pollInterval)
        }
        return agent
    }

    func add(_ key: SSHKeyPair, comment: String) async throws {
        let result = try await ChildProcess(
            executableURL: tools.add,
            arguments: ["-q", "-t", String(Self.keyLifetimeSeconds), "-"],
            environment: SSHTools.environment(adding: ["SSH_AUTH_SOCK": socket.fileSystemPath]),
            input: key.privateKeyFile(comment: comment)
        ).run()
        guard result.status == 0 else { throw SSHAgentError.couldNotAddKey(status: result.status) }
    }

    /// The agent removes its socket and forgets its key on SIGTERM.
    func stop() {
        if process.isRunning { process.terminate() }
    }

    private static func isSocket(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.fileSystemPath, &info) == 0 && info.st_mode & S_IFMT == S_IFSOCK
    }
}
