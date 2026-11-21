/// One interface's line of `/proc/net/dev`: its name and a colon, then eight received figures
/// (bytes, packets, errors, drops, ...) and eight sent, in the same order.
///
///       eth0: 236775442    9985    0    0    0     0          0         0   836234    8596    0    0 ...
struct InterfaceCounters: Equatable {
    var name: String
    var receivedBytes: UInt64
    var receiveErrors: UInt64
    var receiveDrops: UInt64
    var sentBytes: UInt64
    var sendErrors: UInt64
    var sendDrops: UInt64

    init(
        name: String,
        receivedBytes: UInt64,
        receiveErrors: UInt64,
        receiveDrops: UInt64,
        sentBytes: UInt64,
        sendErrors: UInt64,
        sendDrops: UInt64
    ) {
        self.name = name
        self.receivedBytes = receivedBytes
        self.receiveErrors = receiveErrors
        self.receiveDrops = receiveDrops
        self.sentBytes = sentBytes
        self.sendErrors = sendErrors
        self.sendDrops = sendDrops
    }

    /// The two header lines have no colon after a name and are skipped. A long name can run into its
    /// first figure, as in `docker_gwbridge:0`.
    init?(parsing line: Substring) {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let numbers = line[line.index(after: colon)...].split(byte: " ").compactMap { UInt64($0) }
        guard numbers.count >= 16 else { return nil }
        self.init(
            name: String(line[..<colon].trimmingWhitespace()),
            receivedBytes: numbers[0],
            receiveErrors: numbers[2],
            receiveDrops: numbers[3],
            sentBytes: numbers[8],
            sendErrors: numbers[10],
            sendDrops: numbers[11]
        )
    }

    static func all(parsing text: String) -> [InterfaceCounters] {
        text.lines.compactMap(InterfaceCounters.init(parsing:))
    }
}
