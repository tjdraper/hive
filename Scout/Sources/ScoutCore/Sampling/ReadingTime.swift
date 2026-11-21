/// When a reading was taken, by the kernel's clock since the server started, so the time between two
/// readings stays right when the wall clock is changed, and none is given across a restart, after
/// which every counter has started again.
struct ReadingTime: Equatable {
    /// `/proc/sys/kernel/random/boot_id`, new each time the server starts.
    let bootID: String?
    let uptimeSeconds: Double

    init(bootID: String?, uptimeSeconds: Double) {
        self.bootID = bootID
        self.uptimeSeconds = uptimeSeconds
    }

    init?(files: SystemFiles) {
        guard let uptime = files.text(at: "/proc/uptime").flatMap(ServerFactsReader.uptime(parsing:)) else { return nil }
        let bootID = files.text(at: "/proc/sys/kernel/random/boot_id").map { String($0[...].trimmingWhitespace()) }
        self.init(bootID: bootID, uptimeSeconds: uptime)
    }

    /// Seconds since `earlier`, or nil when there's no earlier reading to work out rates from, or the
    /// server has restarted since.
    func seconds(since earlier: ReadingTime?) -> Double? {
        guard let earlier, earlier.bootID == bootID, uptimeSeconds > earlier.uptimeSeconds else { return nil }
        return uptimeSeconds - earlier.uptimeSeconds
    }
}
