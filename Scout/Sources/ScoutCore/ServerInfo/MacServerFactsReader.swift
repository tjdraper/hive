#if os(macOS)
import Darwin
import ScoutProtocol

/// What a Mac is: how long it's been up, its macOS version and its kernel's.
enum MacServerFactsReader {
    static func read() -> ServerFacts {
        ServerFacts(
            uptimeSeconds: bootedAt().map { max(0, Double(SampleSchedule.now()) / 1_000_000_000 - $0) },
            distribution: distribution(
                version: MacSysctl.string("kern.osproductversion"),
                build: MacSysctl.string("kern.osversion")
            ),
            kernel: MacSysctl.string("kern.osrelease").map { "Darwin \($0)" },
            scoutVersion: ScoutRelease.version.description,
            processesHidden: false
        )
    }

    /// Such as "macOS 27.2 (26B123)", as About This Mac gives it.
    static func distribution(version: String?, build: String?) -> String? {
        guard let version else { return nil }
        return build.map { "macOS \(version) (\($0))" } ?? "macOS \(version)"
    }

    /// Seconds since 1970, by the wall clock when the Mac started.
    static func bootedAt() -> Double? {
        MacSysctl.value("kern.boottime", as: timeval.self).map { Double($0.tv_sec) + Double($0.tv_usec) / 1_000_000 }
    }
}
#endif
