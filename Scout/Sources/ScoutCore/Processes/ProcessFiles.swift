/// What Scout reads of one process, parsed from the bytes of its files without making a string of
/// each, since a server has hundreds of processes and they're read every sample
/// (https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html).
enum ProcessFiles {
    struct Stat: Equatable {
        /// The kernel's name for the command, at most 15 bytes.
        var command: String
        /// `Z` for a zombie.
        var state: UInt8
        /// User and system time, in clock ticks.
        var cpuTicks: UInt64
        /// When the process started, in clock ticks since the server started. With the process ID,
        /// it tells a process apart from a later one given the same ID.
        var startTicks: UInt64
        /// A thread of the kernel's own, such as `kworker`, which has no memory of its own.
        var isKernelThread: Bool
    }

    /// `PF_KTHREAD` in the process's flags (https://github.com/torvalds/linux/blob/master/include/linux/sched.h).
    private static let kernelThreadFlag: UInt64 = 0x0020_0000

    /// `/proc/<pid>/stat`: `1234 (php-fpm: pool www) S 1 ...`. The command is in parentheses and can
    /// hold spaces and parentheses itself, so it runs to the last closing one. The fields after it are
    /// numbered from 3, the state; the flags are 9, user and system time 14 and 15, and the start time 22.
    static func stat(parsing bytes: ArraySlice<UInt8>) -> Stat? {
        guard let open = bytes.firstIndex(of: UInt8(ascii: "(")),
              let close = bytes.lastIndex(of: UInt8(ascii: ")")),
              open < close, close + 2 < bytes.endIndex
        else { return nil }
        let fields = numbers(in: bytes[(close + 2)...], count: 20)
        guard fields.count == 20 else { return nil }
        // swiftlint:disable:next optional_data_string_conversion
        let command = String(decoding: bytes[(open + 1)..<close], as: UTF8.self)
        return Stat(
            command: command,
            state: bytes[close + 2],
            cpuTicks: fields[11] + fields[12],
            startTicks: fields[19],
            isKernelThread: fields[6] & kernelThreadFlag != 0
        )
    }

    /// `/proc/<pid>/statm`: sizes in pages, of which the second is resident memory and the third the
    /// part of it that's shared, such as libraries and files mapped into memory.
    static func ownMemoryPages(parsing bytes: ArraySlice<UInt8>) -> UInt64? {
        let fields = numbers(in: bytes, count: 3)
        guard fields.count == 3 else { return nil }
        return fields[1] - min(fields[2], fields[1])
    }

    /// The first `count` fields separated by spaces, each a decimal number, or zero for one that isn't,
    /// such as the state letter.
    private static func numbers(in bytes: ArraySlice<UInt8>, count: Int) -> [UInt64] {
        var fields: [UInt64] = []
        fields.reserveCapacity(count)
        var value: UInt64 = 0
        var inField = false
        for byte in bytes {
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") {
                if inField {
                    fields.append(value)
                    if fields.count == count { return fields }
                }
                value = 0
                inField = false
            } else {
                inField = true
                if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                    value = value &* 10 &+ UInt64(byte - UInt8(ascii: "0"))
                }
            }
        }
        if inField { fields.append(value) }
        return fields
    }
}
