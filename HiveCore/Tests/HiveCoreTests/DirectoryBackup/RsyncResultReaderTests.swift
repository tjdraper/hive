import Foundation
@testable import HiveCore
import HiveKit
import Testing

/// Output recorded from rsync 3.5.2, pulling from the test server's rsync 3.2.7 or between folders on the Mac.
struct RsyncResultReaderTests {
    private static func result(_ status: Int32, output: String = "", error: String = "") -> ChildProcess.Result {
        ChildProcess.Result(status: status, standardOutput: Data(output.utf8), standardError: Data(error.utf8))
    }

    static let listing = """
    drwxr-xr-x             38 2026/11/06 11:01:13 .
    drwxr-xr-x              8 2026/11/06 11:01:13 config
    -rw-r--r--         10,240 2026/11/06 11:01:13 read me.txt

    """

    static let emptyListing = "drwxr-xr-x             64 2026/11/06 11:21:52 .\n"

    static let missing = """
    rsync: [sender] change_dir "/srv/nope" failed: No such file or directory (2)
    rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1987) [Receiver=3.5.2]
    rsync: [Receiver] write error: Broken pipe (32)

    """

    static let notADirectory = """
    rsync: [sender] change_dir "/tmp/exp3/file" failed: Not a directory (20)
    rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1416) [sender=3.5.2]

    """

    static let unreadable = """
    rsync: [sender] change_dir "/var/root" failed: Permission denied (13)
    rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1416) [sender=3.5.2]

    """

    static let unreadableFile = """
    rsync: [sender] send_files failed to open "/tmp/exp3/src/locked.txt": Permission denied (13)
    rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1416) [sender=3.5.2]

    """

    static let refusedLogin = """
    root@127.0.0.1: Permission denied (publickey).
    rsync: connection unexpectedly closed (0 bytes received so far) [Receiver]
    rsync error: unexplained error (code 255) at io.c(303) [Receiver=3.5.2]

    """

    static let refusedConnection = """
    ssh: connect to host 127.0.0.1 port 2299: Connection refused
    rsync: connection unexpectedly closed (0 bytes received so far) [Receiver]
    rsync error: unexplained error (code 255) at io.c(303) [Receiver=3.5.2]

    """

    static let statistics = """
    Number of files: 12 (reg: 7, dir: 4, link: 1)
    Number of created files: 12 (reg: 7, dir: 4, link: 1)
    Number of deleted files: 0
    Number of regular files transferred: 7
    Total file size: 300059 bytes
    Total transferred file size: 300059 bytes
    Literal data: 300059 bytes
    Matched data: 0 bytes
    File list size: 0
    Total bytes sent: 210
    Total bytes received: 300920

    sent 210 bytes  received 300920 bytes  602260.00 bytes/sec
    total size is 300059  speedup is 1.00

    """

    @Test("A listing with anything besides the folder itself has files, and one with only the folder is empty")
    func listings() {
        // Act, Assert
        #expect(RsyncResultReader.listing(in: Self.result(0, output: Self.listing)) == .hasFiles)
        #expect(RsyncResultReader.listing(in: Self.result(0, output: Self.emptyListing)) == .empty)
        #expect(RsyncResultReader.listing(in: Self.result(0, output: "")) == .empty)
    }

    @Test("A missing folder, a file in its place and an unreadable one are told apart from each other and from a failed connection")
    func listingFailures() {
        // Act, Assert
        #expect(RsyncResultReader.listing(in: Self.result(23, error: Self.missing)) == .failed(.sourceMissing))
        #expect(RsyncResultReader.listing(in: Self.result(23, error: Self.notADirectory)) == .failed(.sourceMissing))
        #expect(RsyncResultReader.listing(in: Self.result(23, error: Self.unreadable)) == .failed(.sourceUnreadable))
        #expect(RsyncResultReader.listing(in: Self.result(255, error: Self.refusedLogin)) == .failed(.loginRefused))
        #expect(RsyncResultReader.listing(in: Self.result(255, error: Self.refusedConnection)) == .failed(.unreachable))
        #expect(RsyncResultReader.listing(in: Self.result(255, error: SSHFailureReaderTests.changedKey)) == .failed(.hostKeyChanged))
    }

    @Test("A pull's failures are read from its status and messages")
    func pullFailures() {
        // Act, Assert
        #expect(RsyncResultReader.pull(Self.result(23, error: Self.unreadableFile)).failure == .someFilesNotTransferred)
        #expect(RsyncResultReader.pull(Self.result(30)).failure == .stalled)
        #expect(RsyncResultReader.pull(Self.result(20)).failure == .cancelled)
        #expect(RsyncResultReader.pull(Self.result(255, error: SSHFailureReaderTests.changedKey)).failure == .hostKeyChanged)
        #expect(RsyncResultReader.pull(Self.result(12)).failure == .failed)
    }

    @Test("Files that vanish mid-run are a warning, not a failure")
    func vanishedFilesWarn() {
        // Act
        let outcome = RsyncResultReader.pull(Self.result(24, output: Self.statistics))

        // Assert
        #expect(outcome.failure == nil)
        #expect(outcome.vanishedFiles)
    }

    @Test("What was transferred is read from rsync's statistics, with or without thousands separators")
    func statistics() {
        // Act
        let plain = RsyncResultReader.statistics(in: Data(Self.statistics.utf8))
        let separated = RsyncResultReader.statistics(
            in: Data("Total bytes received: 1,300,920\nNumber of regular files transferred: 1,024\n".utf8)
        )

        // Assert
        #expect(plain == PullStatistics(filesTransferred: 7, bytesTransferred: 300_059, bytesReceived: 300_920))
        #expect(separated == PullStatistics(filesTransferred: 1024, bytesTransferred: 0, bytesReceived: 1_300_920))
    }
}
