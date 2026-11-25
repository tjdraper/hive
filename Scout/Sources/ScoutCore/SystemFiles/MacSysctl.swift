#if os(macOS)
import Darwin

/// Reads the kernel's values on a Mac by name, as `sysctl -n` does. A Mac has no `/proc`.
enum MacSysctl {
    static func value<Value>(_ name: String, as _: Value.Type) -> Value? {
        var size = MemoryLayout<Value>.size
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<Value>.alignment)
        defer { pointer.deallocate() }
        guard sysctlbyname(name, pointer, &size, nil, 0) == 0, size == MemoryLayout<Value>.size else { return nil }
        return pointer.load(as: Value.self)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The host port, asked for once: each call to `mach_host_self` adds a reference to it that's never given back.
    static let host = mach_host_self()
}
#endif
