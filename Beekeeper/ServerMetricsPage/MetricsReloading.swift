import SwiftUI

extension View {
    /// Loads now, again whenever `id` changes, as `task(id:)` does, and every `interval` after that, or
    /// only once for none. Not while Beekeeper is in the background, where iOS stops it anyway, and at once
    /// when it comes back, so a page shows what it missed without waiting for its next turn.
    func reloading(every interval: Duration?, id: some Equatable, _ load: @escaping () async -> Void) -> some View {
        modifier(MetricsReloading(interval: interval, id: id, load: load))
    }
}

private struct MetricsReloading<ID: Equatable>: ViewModifier {
    private struct Key: Equatable {
        let id: ID
        let inBackground: Bool
    }

    let interval: Duration?
    let id: ID
    let load: () async -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: Key(id: id, inBackground: scenePhase == .background)) {
            guard scenePhase != .background else { return }
            await load()
            guard let interval else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }
}
