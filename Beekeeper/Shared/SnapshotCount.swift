/// "1 snapshot" or "3 snapshots", for text built outside a `Text`, which can't inflect it.
struct SnapshotCount: CustomStringConvertible {
    let count: Int

    init(_ count: Int) {
        self.count = count
    }

    var description: String {
        count == 1 ? "1 snapshot" : "\(count) snapshots"
    }
}
