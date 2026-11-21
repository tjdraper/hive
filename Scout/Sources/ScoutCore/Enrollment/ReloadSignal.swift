#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import NIOCore
import NIOPosix

// Written once, before the signal handler that reads it is installed, and never again.
// swiftlint:disable:next nonisolated_unsafe
nonisolated(unsafe) private var reloadPipeInput: Int32 = -1

public enum ReloadSignalError: Error, Equatable {
    case couldNotListen(errno: Int32)
}

/// SIGHUP, which the service manager sends to have a running Scout read its enrollment again after
/// enrolling anew. A signal handler can do almost nothing safely, so it writes a byte to a pipe that
/// the event loop reads, rather than starting a thread to wait for it.
public enum ReloadSignal {
    /// One element for each SIGHUP, or for several that arrive together. Call once.
    public static func listen(on eventLoop: ScoutEventLoop) async throws -> AsyncStream<Void> {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw ReloadSignalError.couldNotListen(errno: errno) }
        for descriptor in descriptors {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }
        // A pipe already full holds a reload still to be read, so the handler never has to wait.
        _ = fcntl(descriptors[1], F_SETFL, O_NONBLOCK)
        let (signals, input) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        _ = try await NIOPipeBootstrap(group: eventLoop.loop)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture { try channel.pipeline.syncOperations.addHandler(ReloadPipeReader(signals: input)) }
            }
            .takingOwnershipOfDescriptor(input: descriptors[0])
            .get()
        reloadPipeInput = descriptors[1]
        signal(SIGHUP) { _ in
            let saved = errno
            var byte: UInt8 = 0
            _ = write(reloadPipeInput, &byte, 1)
            errno = saved
        }
        return signals
    }
}

private final class ReloadPipeReader: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    let signals: AsyncStream<Void>.Continuation

    init(signals: AsyncStream<Void>.Continuation) {
        self.signals = signals
    }

    func channelRead(context _: ChannelHandlerContext, data _: NIOAny) {
        signals.yield()
    }
}
