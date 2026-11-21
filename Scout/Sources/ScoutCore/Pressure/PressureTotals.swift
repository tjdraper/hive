/// Microseconds work has been stalled on one resource since the server started, from one of
/// `/proc/pressure`'s files (https://docs.kernel.org/accounting/psi.html):
///
///     some avg10=0.00 avg60=0.00 avg300=0.00 total=12345
///     full avg10=0.00 avg60=0.00 avg300=0.00 total=678
///
/// The totals are used rather than the kernel's averages, so a sample covers exactly the time since
/// the previous one.
struct PressureTotals: Equatable {
    var some: UInt64
    var full: UInt64?

    init(some: UInt64, full: UInt64?) {
        self.some = some
        self.full = full
    }

    init?(parsing text: String) {
        var some: UInt64?
        var full: UInt64?
        for line in text.lines {
            let fields = line.split(byte: " ")
            guard let kind = fields.first,
                  let total = fields.first(where: { $0.hasPrefix("total=") }).flatMap({ UInt64($0.dropFirst("total=".count)) })
            else { continue }
            switch kind {
            case "some": some = total
            case "full": full = total
            default: continue
            }
        }
        guard let some else { return nil }
        self.init(some: some, full: full)
    }
}
