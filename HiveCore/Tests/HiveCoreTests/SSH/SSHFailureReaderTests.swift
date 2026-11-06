import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// `ssh`'s own output, recorded from the Mac's OpenSSH 10.5 against the test server and unreachable addresses,
/// except where a case says otherwise.
struct SSHFailureReaderTests {
    struct Recording: Sendable, CustomTestStringConvertible {
        let name: String
        let status: Int32
        let standardError: String
        let failure: ConnectionFailure?

        var testDescription: String {
            name
        }
    }

    /// Recorded after `Scripts/test-server.sh new-host-key`, with the run folder's path shortened. The
    /// fingerprint line alone ends without `\r`.
    static let changedKey = [
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\r\n",
        "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\r\n",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\r\n",
        "IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!\r\n",
        "Someone could be eavesdropping on you right now (man-in-the-middle attack)!\r\n",
        "It is also possible that a host key has just been changed.\r\n",
        "The fingerprint for the ED25519 key sent by the remote host is\n",
        "SHA256:lAmGjy0b+lxPHn/0NTYWlZifvTthWekXALNvSW1gerI.\r\n",
        "Please contact your system administrator.\r\n",
        "Add correct host key in /var/folders/p6/T/hive-ssh.egQAng/known_hosts to get rid of this message.\r\n",
        "Offending ED25519 key in /var/folders/p6/T/hive-ssh.egQAng/known_hosts:1\r\n",
        "Host key for 6f1c2a4e-3d1b-4a51-9a0e-2f4c1b7d8e90 has changed and you have requested strict checking.\r\n",
        "Host key verification failed.\r\n",
    ].joined()

    static let recordings = [
        Recording(name: "connected", status: 0, standardError: "", failure: nil),
        Recording(name: "changed host key", status: 255, standardError: changedKey, failure: .hostKeyChanged),
        // OpenSSH's wording, for a server that no longer offers the confirmed key's type.
        Recording(
            name: "host key of another type",
            status: 255,
            standardError: """
            No ED25519 host key is known for 6f1c2a4e-3d1b-4a51-9a0e-2f4c1b7d8e90 and you have requested strict checking.
            Host key verification failed.

            """,
            failure: .hostKeyChanged
        ),
        Recording(
            name: "refused login",
            status: 255,
            standardError: "root@127.0.0.1: Permission denied (publickey).\r\n",
            failure: .loginRefused
        ),
        Recording(
            name: "refused connection",
            status: 255,
            standardError: "ssh: connect to host 127.0.0.1 port 9: Connection refused\r\n",
            failure: .unreachable
        ),
        Recording(
            name: "unknown host",
            status: 255,
            standardError: "ssh: Could not resolve hostname nonexistent.invalid: nodename nor servname provided, or not known\r\n",
            failure: .unreachable
        ),
        Recording(
            name: "no answer",
            status: 255,
            standardError: "ssh: connect to host 10.255.255.1 port 81: Operation timed out\r\n",
            failure: .unreachable
        ),
        // OpenSSH's wording, as a stall is hard to cause on purpose.
        Recording(
            name: "stalled",
            status: 255,
            standardError: "Timeout, server 127.0.0.1 not responding.\r\n",
            failure: .stalled
        ),
        Recording(name: "command failed on the server", status: 3, standardError: "", failure: .failed),
        Recording(name: "an error not recognized", status: 255, standardError: "something unexpected\r\n", failure: .failed),
        Recording(name: "command failed on the server with output", status: 3, standardError: "Permission denied\n", failure: .failed),
    ]

    @Test("A recorded failure is told apart from the others", arguments: recordings)
    func readsRecording(recording: Recording) {
        // Arrange
        let output = Data(recording.standardError.utf8)
        let result = ChildProcess.Result(status: recording.status, standardOutput: Data(), standardError: output)

        // Act
        let failure = SSHFailureReader.failure(in: result)

        // Assert
        #expect(failure == recording.failure)
    }
}
