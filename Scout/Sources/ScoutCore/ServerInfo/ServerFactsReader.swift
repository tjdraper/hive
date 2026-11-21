import ScoutProtocol

/// Reads what the server is: how long it's been up, its distribution and its kernel.
struct ServerFactsReader {
    let files: SystemFiles

    func read(processesHidden: Bool) -> ServerFacts {
        ServerFacts(
            uptimeSeconds: files.text(at: "/proc/uptime").flatMap(Self.uptime(parsing:)),
            distribution: osRelease()?.distribution,
            kernel: files.text(at: "/proc/sys/kernel/osrelease")?.lines.first.map(String.init),
            scoutVersion: ScoutRelease.version,
            processesHidden: processesHidden
        )
    }

    /// The first of `/proc/uptime`'s two figures, seconds since the server started.
    static func uptime(parsing text: String) -> Double? {
        text.split(byte: " ").first.flatMap { Double($0) }
    }

    /// `/etc/os-release` is the standard place, and `/usr/lib/os-release` where a distribution has no copy in `/etc`.
    private func osRelease() -> OSRelease? {
        let text = files.text(at: "/etc/os-release") ?? files.text(at: "/usr/lib/os-release")
        return text.map(OSRelease.init(parsing:))
    }
}
