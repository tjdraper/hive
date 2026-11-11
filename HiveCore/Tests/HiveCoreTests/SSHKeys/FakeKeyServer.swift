import Foundation
@testable import HiveCore
import Synchronization

/// Stands in for a server's `sshd` without `ssh`: it accepts a key found in its `authorized_keys`, as
/// `sshd` does, then runs the command with this Mac's `sh` in a temporary home folder, so the scripts
/// that change the file run for real.
final class FakeKeyServer: SSHRunning {
    private struct State {
        /// Keys accepted whether or not they're in the file, as when `sshd` reads keys from elsewhere too.
        var alsoAccepted: Set<OpenSSHPublicKey> = []
        /// When set, only these are accepted, as when `sshd` reads keys only from elsewhere.
        var onlyAccepted: Set<OpenSSHPublicKey>?
        var failsRemoval = false
        var commands: [(command: String, key: OpenSSHPublicKey)] = []
    }

    let home: TemporaryDirectory
    private let state = Mutex(State())

    init(lines: [String]) throws {
        home = try TemporaryDirectory()
        let folder = home.url.appending(path: ".ssh", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(lines.map { $0 + "\n" }.joined())
    }

    var authorizedKeys: URL {
        home.url.appending(path: ".ssh/authorized_keys", directoryHint: .notDirectory)
    }

    var contents: String {
        get throws { try String(contentsOf: authorizedKeys, encoding: .utf8) }
    }

    var lines: [String] {
        get throws { try contents.split(separator: "\n").map(String.init) }
    }

    var commands: [(command: String, key: OpenSSHPublicKey)] {
        state.withLock { $0.commands }
    }

    func write(_ contents: String) throws {
        try Data(contents.utf8).write(to: authorizedKeys)
    }

    func alsoAccept(_ key: OpenSSHPublicKey) {
        _ = state.withLock { $0.alsoAccepted.insert(key) }
    }

    func acceptOnly(_ keys: Set<OpenSSHPublicKey>) {
        state.withLock { $0.onlyAccepted = keys }
    }

    func failRemoval() {
        state.withLock { $0.failsRemoval = true }
    }

    func run(_ remoteCommand: String, on target: SSHTarget) async throws -> ChildProcess.Result {
        let key = target.key.publicKey
        let (only, also, failsRemoval) = state.withLock { state in
            state.commands.append((remoteCommand, key))
            return (state.onlyAccepted, state.alsoAccepted, state.failsRemoval)
        }
        let inFile = AuthorizedKeysFile.entries(for: key, in: (try? Data(contentsOf: authorizedKeys)) ?? Data())
        let accepted = only.map { $0.contains(key) } ?? (!inFile.isEmpty || also.contains(key))
        guard accepted else {
            return ChildProcess.Result(
                status: SSHFailureReader.sshErrorStatus,
                standardOutput: Data(),
                standardError: Data("backup@web.example.com: Permission denied (publickey).\n".utf8)
            )
        }
        if failsRemoval, remoteCommand.contains(".hive-rotation") {
            return ChildProcess.Result(status: 5, standardOutput: Data(), standardError: Data())
        }
        return try await ChildProcess(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", remoteCommand],
            environment: ["HOME": home.url.fileSystemPath, "PATH": "/usr/bin:/bin"]
        ).run()
    }
}
