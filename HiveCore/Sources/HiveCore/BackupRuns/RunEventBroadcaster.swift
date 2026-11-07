import HiveKit
import Synchronization

/// Passes each run event to everyone listening, for D3's WebSocket.
final class RunEventBroadcaster: Sendable {
    /// A listener that falls this far behind loses the oldest events rather than holding the rest up.
    private static let buffered = 200

    private let listeners = Mutex<[Int: AsyncStream<RunEvent>.Continuation]>([:])
    private let nextID = Mutex(0)

    /// Events from now on, until the stream is dropped.
    func listen() -> AsyncStream<RunEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RunEvent.self, bufferingPolicy: .bufferingNewest(Self.buffered))
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

    func send(_ event: RunEvent) {
        for listener in listeners.withLock({ Array($0.values) }) {
            listener.yield(event)
        }
    }
}
