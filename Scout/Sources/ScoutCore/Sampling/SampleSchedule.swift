#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Samples are taken on the wall clock's 10-second marks, so every server's samples line up.
public enum SampleSchedule {
    public static let intervalSeconds: Int64 = 10

    /// The wall clock, in nanoseconds since 1970.
    public static func now() -> Int64 {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        return Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
    }

    /// The first mark strictly after `nanoseconds`, in nanoseconds since 1970.
    public static func nextMark(after nanoseconds: Int64) -> Int64 {
        let interval = intervalSeconds * 1_000_000_000
        return (nanoseconds / interval + 1) * interval
    }
}
