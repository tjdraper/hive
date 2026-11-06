/// Where a run reads directories and dumps databases from.
enum BackupOrigin: Sendable {
    case server(SSHTarget)
    /// This Mac, with the server's folders and tools standing in as folders and scripts. Tests use it,
    /// since they never run `ssh`.
    case thisMac
}
