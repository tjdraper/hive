import Foundation

/// The emails for servers' figures (§8). Readings are from when the alert opened, so a reminder says so.
enum MetricAlertEmail {
    static func stoppedReporting(_ server: StoppedServer, isReminder: Bool, text: AlertText) throws -> EmailMessage {
        let name = try text.server(server.serverID)
        let lines = [
            "\(name) hasn't sent its figures since \(text.date(server.lastReportAt)).",
            "",
            """
            The server may be down or unreachable, or its Scout stopped. Check that the server is up, that it can reach the \
            Hive Mac, and that hive-scout is running on it.
            """,
            "",
            "You'll get a reminder each day until it reports again, and an email once it does.",
        ]
        return EmailMessage(
            subject: isReminder ? "Still not reporting: \(name)" : "Stopped reporting: \(name)",
            body: lines.joined(separator: "\n")
        )
    }

    static func stoppedTogether(_ servers: [StoppedServer], isReminder: Bool, text: AlertText) throws -> EmailMessage {
        var lines = ["\(servers.count) servers stopped sending their figures at about the same time:", ""]
        for server in servers {
            lines.append("\(try text.server(server.serverID)), last heard from \(text.date(server.lastReportAt))")
        }
        lines += [
            "",
            """
            When several stop together, the cause is usually the Hive Mac's own connection, such as its network or Tailscale, \
            rather than the servers.
            """,
            "",
            "You'll get a reminder each day until they report again, and an email once they do.",
        ]
        return EmailMessage(
            subject: isReminder ? "Still not reporting: \(servers.count) servers" : "\(servers.count) servers stopped reporting",
            body: lines.joined(separator: "\n")
        )
    }

    static func clockAhead(serverID: UUID, offsetSeconds: Int64?, isReminder: Bool, text: AlertText) throws -> EmailMessage {
        let name = try text.server(serverID)
        let ahead = offsetSeconds.map { " by about \(duration(seconds: $0))" } ?? ""
        let lines = [
            "\(name)'s clock is ahead of the Hive Mac's\(ahead), so far that Hive can't place its figures and turns them away.",
            "",
            "Set the server's clock right, such as by turning on time synchronization with `timedatectl set-ntp true`.",
            "Its figures are lost until then.",
            "",
            "You'll get a reminder each day until Hive takes its figures again.",
        ]
        return EmailMessage(
            subject: isReminder ? "Still: \(name)'s clock is ahead" : "Clock ahead: \(name)",
            body: lines.joined(separator: "\n")
        )
    }

    static func filesystemFilling(
        serverID: UUID,
        mountPoint: String,
        reading: FilesystemReading,
        since: Date?,
        text: AlertText
    ) throws -> EmailMessage {
        let name = try text.server(serverID)
        let filesystem = "“\(mountPoint)” on \(name)"
        var lines: [String] = []
        if let since { lines += ["This started on \(text.date(since)). Then:", ""] }
        if let used = reading.usedShare { lines.append("The filesystem \(filesystem) is \(percent(used)) full.") }
        if let inodes = reading.inodesUsedShare {
            lines.append("""
            \(percent(inodes)) of the inodes of \(filesystem) are used. A filesystem can run out of inodes, one for each file, \
            with space left, from many small files such as sessions or caches.
            """)
        }
        if let fillsAt = reading.fillsAt {
            lines.append("At the rate \(filesystem) filled over the last week, it's full by about \(text.date(serverTime(fillsAt))).")
        }
        lines += ["", "You'll get a reminder each day until it has room again."]
        return EmailMessage(
            subject: since == nil ? "Disk filling up: \(filesystem)" : "Still filling up: \(filesystem)",
            body: lines.joined(separator: "\n")
        )
    }

    static func memoryShort(serverID: UUID, reading: MemoryReading, text: AlertText) throws -> EmailMessage {
        let name = try text.server(serverID)
        var lines = ["\(name) has been short of memory for \(reading.minutes) minutes:", ""]
        if let available = reading.availableShare {
            lines.append("Only \(percent(available)) of its memory was available, on average.")
        }
        if let swapIn = reading.swapInPagesPerSecond {
            lines.append("""
            It swapped in \(Int(swapIn.rounded())) pages a second, on average. Swapping in steadily means it's short of memory, \
            where swap merely in use often isn't.
            """)
        }
        lines += [
            "",
            "Its processes and containers at the time are on its page in Beekeeper.",
            "You won't get another email about this until it's had enough memory for an hour.",
        ]
        return EmailMessage(subject: "Short of memory: \(name)", body: lines.joined(separator: "\n"))
    }

    static func cpuBusy(serverID: UUID, reading: CPUReading, text: AlertText) throws -> EmailMessage {
        let name = try text.server(serverID)
        var lines = ["\(name)'s CPU has been busy for \(reading.minutes) minutes:", ""]
        if let busy = reading.busyShare { lines.append("Its CPU was \(percent(busy)) busy, on average.") }
        if let steal = reading.stealShare {
            lines.append("""
            Its host took \(percent(steal)) of its CPU time for others (steal), on average, the usual reason a virtual server \
            is slow while looking idle.
            """)
        }
        if let load = reading.loadPerCore {
            lines.append("Its load was \(String(format: "%.1f", load)) for each core, on average.")
        }
        lines += [
            "",
            "Its processes and containers at the time are on its page in Beekeeper.",
            "You won't get another email about this until its CPU has been within its limits for an hour.",
        ]
        return EmailMessage(subject: "CPU busy: \(name)", body: lines.joined(separator: "\n"))
    }

    static func reportingAgain(serverIDs: [UUID], since date: Date, text: AlertText) throws -> EmailMessage {
        let names = try serverIDs.map(text.server)
        guard names.count > 1 else {
            let name = names.first ?? "A removed server"
            return EmailMessage(
                subject: "Reporting again: \(name)",
                body: "\(name) is sending its figures again, since \(text.date(date))."
            )
        }
        let lines = ["These servers are sending their figures again, since \(text.date(date)):", ""] + names
        return EmailMessage(subject: "\(names.count) servers reporting again", body: lines.joined(separator: "\n"))
    }

    static func serverRestarted(serverID: UUID, bootedAt: Int64, text: AlertText) throws -> EmailMessage {
        let name = try text.server(serverID)
        return EmailMessage(
            subject: "Restarted: \(name)",
            body: """
            \(name) restarted at about \(text.date(serverTime(bootedAt))), by its own clock.

            If nobody restarted it, it may have crashed, or been restarted by its provider.
            """
        )
    }

    /// Seconds since 1970 on a server's clock, which is close enough to the Hive Mac's for an email.
    private static func serverTime(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    private static func duration(seconds: Int64) -> String {
        let minutes = (seconds + 30) / 60
        if minutes < 60 { return minutes == 1 ? "a minute" : "\(minutes) minutes" }
        let hours = (minutes + 30) / 60
        if hours < 48 { return hours == 1 ? "an hour" : "\(hours) hours" }
        return "\((hours + 12) / 24) days"
    }
}
