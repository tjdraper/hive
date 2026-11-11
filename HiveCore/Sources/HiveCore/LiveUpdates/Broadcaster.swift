import Synchronization

/// Passes each value to everyone listening, such as each device's live updates.
final class Broadcaster<Value: Sendable>: Sendable {
    /// A listener that falls this far behind loses the oldest values rather than holding the rest up.
    private static var buffered: Int {
        200
    }

    private let listeners = Mutex<[Int: AsyncStream<Value>.Continuation]>([:])
    private let nextID = Mutex(0)

    var listenerCount: Int {
        listeners.withLock { $0.count }
    }

    /// Values from now on, until the stream is dropped.
    func listen() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingNewest(Self.buffered))
        let id = nextID.withLock { id in
            id += 1
            return id
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.listeners.withLock { $0.removeValue(forKey: id) }
        }
        listeners.withLock { $0[id] = continuation }
        return stream
    }

    func send(_ value: Value) {
        for listener in listeners.withLock({ Array($0.values) }) {
            listener.yield(value)
        }
    }
}
