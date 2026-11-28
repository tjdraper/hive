#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import NIOCore
import NIOPosix
import ScoutProtocol

public enum SampleHandoverError: Error, Equatable {
    case couldNotStart(errno: Int32)
    /// The process taking the samples has stopped.
    case couldNotHand(errno: Int32)
    case notASample
    case ended
}

/// Samples handed from one Scout process to another, one line of JSON each, down a pipe that goes one
/// way only. On a Mac, `run` keeps root to read every process, and hands each sample to the `send` it
/// starts, which drops to Scout's user and does everything else, so root never reads anything back.
public struct SampleHandover: Sendable {
    /// Far more than a sample takes, which is limited by what Hive accepts.
    static let longestLine = 4 * 1024 * 1024

    let pid: pid_t
    let input: Int32

    /// Starts `arguments` with the pipe's end as its standard input. Its output goes where this
    /// process's does.
    public static func start(_ arguments: [String]) throws(SampleHandoverError) -> Self {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw .couldNotStart(errno: errno) }
        _ = fcntl(descriptors[1], F_SETFD, FD_CLOEXEC)
        // Writing to a process that stopped fails with EPIPE rather than ending this one.
        signal(SIGPIPE, SIG_IGN)
        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        #else
        var actions = posix_spawn_file_actions_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, descriptors[0], STDIN_FILENO)
        posix_spawn_file_actions_addclose(&actions, descriptors[0])
        let argv = arguments.map { strdup($0) } + [nil]
        let environment = ["PATH=/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL=C"]
        let envp = environment.map { strdup($0) } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid = pid_t()
        let result = posix_spawn(&pid, arguments[0], &actions, nil, argv, envp)
        SystemFiles.close(descriptors[0])
        guard result == 0 else {
            SystemFiles.close(descriptors[1])
            throw .couldNotStart(errno: result)
        }
        return Self(pid: pid, input: descriptors[1])
    }

    /// Waits while the pipe is full, which it is only while the other process is busy.
    public func hand(_ sample: MetricsSample) throws(SampleHandoverError) {
        guard let json = try? JSONEncoder().encode(sample) else { throw .notASample }
        var remaining = (Array(json) + [UInt8(ascii: "\n")])[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { write(input, $0.baseAddress, $0.count) }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw .couldNotHand(errno: errno) }
            remaining = remaining.dropFirst(written)
        }
    }

    /// Passes a signal on, such as SIGHUP to read the enrollment again.
    public func passOn(signal number: Int32) {
        kill(pid, number)
    }

    /// The samples handed to this process on `descriptor`, ending with an error when the process handing
    /// them stops.
    public static func samples(
        from descriptor: Int32 = STDIN_FILENO,
        on eventLoop: ScoutEventLoop
    ) async throws -> AsyncThrowingStream<MetricsSample, any Error> {
        let (samples, output) = AsyncThrowingStream.makeStream(of: MetricsSample.self, bufferingPolicy: .bufferingNewest(60))
        _ = try await NIOPipeBootstrap(group: eventLoop.loop)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(SampleLineReader(samples: output))
                }
            }
            .takingOwnershipOfDescriptor(input: descriptor)
            .get()
        return samples
    }
}

private final class SampleLineReader: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    let samples: AsyncThrowingStream<MetricsSample, any Error>.Continuation
    private var line: [UInt8] = []
    private var stopped = false
    private let decoder = JSONDecoder()

    init(samples: AsyncThrowingStream<MetricsSample, any Error>.Continuation) {
        self.samples = samples
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        for byte in buffer.readableBytesView where !stopped {
            if byte == UInt8(ascii: "\n") {
                finishLine(context: context)
            } else {
                line.append(byte)
            }
        }
        if line.count > SampleHandover.longestLine { stop(.notASample, context: context) }
    }

    private func finishLine(context: ChannelHandlerContext) {
        defer { line.removeAll(keepingCapacity: true) }
        guard let sample = try? decoder.decode(MetricsSample.self, from: Data(line)) else {
            return stop(.notASample, context: context)
        }
        samples.yield(sample)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        samples.finish(throwing: SampleHandoverError.ended)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        samples.finish(throwing: error)
        context.close(promise: nil)
    }

    private func stop(_ error: SampleHandoverError, context: ChannelHandlerContext) {
        stopped = true
        samples.finish(throwing: error)
        context.close(promise: nil)
    }
}
