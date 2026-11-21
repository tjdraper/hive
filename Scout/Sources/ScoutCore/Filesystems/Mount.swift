/// One line of `/proc/self/mountinfo`
/// (https://man7.org/linux/man-pages/man5/proc_pid_mountinfo.5.html):
///
///     36 35 98:0 /mnt1 /mnt2 rw,noatime master:1 - ext3 /dev/root rw,errors=continue
///
/// IDs, the device's `major:minor`, the folder of the filesystem mounted, the mount point, mount
/// options, any number of optional fields, a lone `-`, the type, what's mounted and its own options.
struct Mount: Equatable {
    var device: Substring
    var type: Substring
    /// Comma-separated, such as `rw,hidepid=invisible`.
    var superOptions: Substring
    private var escapedMountPoint: Substring
    private var escapedSource: Substring

    /// Paths are unescaped only when they're asked for, since a server can have hundreds of mounts,
    /// such as Docker's, and only its local filesystems are sent.
    var mountPoint: String { Self.unescaped(escapedMountPoint) }
    var source: String { Self.unescaped(escapedSource) }

    init?(parsing line: Substring) {
        let fields = line.split(byte: " ")
        guard fields.count >= 9, let separator = fields[6...].firstIndex(of: "-"), separator + 2 < fields.count else { return nil }
        device = fields[2]
        escapedMountPoint = fields[4]
        type = fields[separator + 1]
        escapedSource = fields[separator + 2]
        superOptions = separator + 3 < fields.count ? fields[separator + 3] : ""
    }

    static func all(parsing text: String) -> [Mount] {
        text.lines.compactMap(Mount.init(parsing:))
    }

    /// The kernel writes a space, tab, newline or backslash in a path as a backslash and three octal digits.
    private static func unescaped(_ field: Substring) -> String {
        guard field.contains("\\") else { return String(field) }
        var bytes: [UInt8] = []
        var utf8 = field.utf8[...]
        while let byte = utf8.popFirst() {
            let digits = utf8.prefix(3)
            if byte == UInt8(ascii: "\\"), digits.count == 3,
               digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "7")).contains($0) }),
               // swiftlint:disable:next optional_data_string_conversion
               let value = UInt8(String(decoding: digits, as: UTF8.self), radix: 8) {
                bytes.append(value)
                utf8 = utf8.dropFirst(3)
            } else {
                bytes.append(byte)
            }
        }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }
}

extension [Mount] {
    /// `/proc` mounted with `hidepid` other than 0 hides other users' processes from Scout.
    var processesHidden: Bool {
        guard let proc = last(where: { $0.type == "proc" && $0.mountPoint == "/proc" }) else { return false }
        return proc.superOptions.split(byte: ",").contains { option in
            option.hasPrefix("hidepid=") && !["hidepid=0", "hidepid=off"].contains(option)
        }
    }
}
