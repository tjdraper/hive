/// What Scout reads of one cgroup, parsed from its files' bytes without making a string of each, since
/// a server can have dozens of containers and services, read every sample. For cgroup v2
/// (https://docs.kernel.org/admin-guide/cgroup-v2.html) and v1
/// (https://docs.kernel.org/admin-guide/cgroup-v1/index.html).
enum CgroupFiles {
    /// v2's `cpu.stat`: `usage_usec 159304413` among other lines, in microseconds. It counts every
    /// process that ran in the cgroup, those that have exited included.
    static func cpuMicroseconds(parsing bytes: ArraySlice<UInt8>) -> UInt64? {
        value(named: "usage_usec", in: bytes)
    }

    /// v1's `cpuacct.usage` in nanoseconds, and v2's `memory.current` and v1's `memory.usage_in_bytes`
    /// in bytes: one number.
    static func number(parsing bytes: ArraySlice<UInt8>) -> UInt64? {
        number(at: bytes.startIndex, in: bytes)
    }

    /// File cache the kernel would reclaim first, from `memory.stat`: `inactive_file` in v2, and
    /// `total_inactive_file`, which counts cgroups below too, in v1. `docker stats` leaves it out of
    /// memory in use.
    static func inactiveFileBytes(parsing bytes: ArraySlice<UInt8>, version: CgroupVersion) -> UInt64? {
        value(named: version == .version2 ? "inactive_file" : "total_inactive_file", in: bytes)
    }

    /// v2's `io.stat`: a line for each device, `253:0 rbytes=40108032 wbytes=30814208 rios=9054 ...`,
    /// added up.
    static func inputOutput(parsingV2 bytes: ArraySlice<UInt8>) -> (read: UInt64, written: UInt64) {
        var read: UInt64 = 0
        var written: UInt64 = 0
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let fieldStart = index
            while index < bytes.endIndex, bytes[index] != space, bytes[index] != newline {
                index += 1
            }
            let field = bytes[fieldStart ..< index]
            if field.starts(with: readBytesKey) { read &+= number(at: fieldStart + readBytesKey.count, in: bytes) ?? 0 }
            if field.starts(with: writtenBytesKey) { written &+= number(at: fieldStart + writtenBytesKey.count, in: bytes) ?? 0 }
            index += 1
        }
        return (read, written)
    }

    /// v1's `blkio.throttle.io_service_bytes_recursive`: `8:0 Read 1234` and `8:0 Write 5678` for each
    /// device, among other operations, then `Total 6912`, added up by device.
    static func inputOutput(parsingV1 bytes: ArraySlice<UInt8>) -> (read: UInt64, written: UInt64) {
        var read: UInt64 = 0
        var written: UInt64 = 0
        for line in bytes.split(separator: newline) {
            let fields = line.split(separator: space)
            guard fields.count == 3, let value = number(parsing: fields[2]) else { continue }
            if fields[1].elementsEqual("Read".utf8) { read &+= value }
            if fields[1].elementsEqual("Write".utf8) { written &+= value }
        }
        return (read, written)
    }

    /// `cgroup.procs`: a process ID a line.
    static func processIDs(parsing bytes: ArraySlice<UInt8>) -> [Int32] {
        var ids: [Int32] = []
        var value: Int32 = 0
        var inNumber = false
        for byte in bytes {
            if byte >= zero, byte <= nine {
                value = value &* 10 &+ Int32(byte - zero)
                inNumber = true
            } else {
                if inNumber { ids.append(value) }
                value = 0
                inNumber = false
            }
        }
        if inNumber { ids.append(value) }
        return ids
    }

    private static let space = UInt8(ascii: " ")
    private static let newline = UInt8(ascii: "\n")
    private static let zero = UInt8(ascii: "0")
    private static let nine = UInt8(ascii: "9")
    private static let readBytesKey = Array("rbytes=".utf8)
    private static let writtenBytesKey = Array("wbytes=".utf8)

    /// The number after `name` and a space at the start of a line.
    private static func value(named name: StaticString, in bytes: ArraySlice<UInt8>) -> UInt64? {
        let key = UnsafeBufferPointer(start: name.utf8Start, count: name.utf8CodeUnitCount)
        var lineStart = bytes.startIndex
        while lineStart < bytes.endIndex {
            let afterKey = lineStart + key.count
            if afterKey < bytes.endIndex, bytes[afterKey] == space, bytes[lineStart ..< afterKey].elementsEqual(key) {
                return number(at: afterKey + 1, in: bytes)
            }
            guard let newlineIndex = bytes[lineStart...].firstIndex(of: newline) else { return nil }
            lineStart = newlineIndex + 1
        }
        return nil
    }

    /// The decimal number starting at `index`, or nil when there's none there.
    private static func number(at index: Int, in bytes: ArraySlice<UInt8>) -> UInt64? {
        var value: UInt64 = 0
        var index = index
        let start = index
        while index < bytes.endIndex, bytes[index] >= zero, bytes[index] <= nine {
            value = value &* 10 &+ UInt64(bytes[index] - zero)
            index += 1
        }
        return index > start ? value : nil
    }
}
