import Foundation
import HiveKit
import Synchronization

/// Each server's newest figures, for live updates. Unlike `Broadcaster`, it keeps no queue: a listener
/// that falls behind finds only each server's newest when it looks, so figures arriving every 10
/// seconds can never push job events out of its buffer.
final class MetricsLiveBoard: Sendable {
    private struct Entry {
        let latest: ServerMetricsLatest
        let version: Int
    }

    private struct State {
        var entries: [UUID: Entry] = [:]
        var version = 0
        var listeners: [Int: AsyncStream<Void>.Continuation] = [:]
        var nextListener = 0
    }

    private let state = Mutex(State())

    /// Ignores figures no newer than those already posted for the server.
    func post(_ latest: ServerMetricsLatest) {
        let listeners = state.withLock { state -> [AsyncStream<Void>.Continuation] in
            if let current = state.entries[latest.serverID], current.latest.takenAt >= latest.takenAt { return [] }
            state.version += 1
            state.entries[latest.serverID] = Entry(latest: latest, version: state.version)
            return Array(state.listeners.values)
        }
        for listener in listeners {
            listener.yield()
        }
    }

    /// A signal after each change from now on, holding at most one while unread, and where the board
    /// stands, for `changes(since:)` to start from.
    func listen() -> (changes: AsyncStream<Void>, seen: [UUID: Int]) {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let (id, seen) = state.withLock { state in
            state.nextListener += 1
            state.listeners[state.nextListener] = continuation
            return (state.nextListener, state.entries.mapValues(\.version))
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.listeners.removeValue(forKey: id) }
        }
        return (stream, seen)
    }

    /// Each server's newest figures not yet in `seen`, which is brought up to date.
    func changes(since seen: inout [UUID: Int]) -> [ServerMetricsLatest] {
        let entries = state.withLock { $0.entries }
        var changed: [ServerMetricsLatest] = []
        for (serverID, entry) in entries where entry.version > seen[serverID] ?? 0 {
            changed.append(entry.latest)
            seen[serverID] = entry.version
        }
        return changed.sorted { $0.serverID.uuidString < $1.serverID.uuidString }
    }
}
