import Darwin
import Foundation
import Synchronization
import zlib

struct DumpFileSummary: Equatable {
    /// How many of the dump's first and last bytes are kept, enough to check how it starts and ends.
    static let keptBytes = 64

    /// What the database wrote, before compression.
    var bytesDumped: Int64 = 0
    /// What went into the file.
    var bytesStored: Int64 = 0
    var beginning = Data()
    var ending = Data()

    mutating func record(_ data: Data) {
        bytesDumped += Int64(data.count)
        if beginning.count < Self.keptBytes { beginning.append(data.prefix(Self.keptBytes - beginning.count)) }
        ending = Data((ending + data).suffix(Self.keptBytes))
    }
}

enum DumpFileError: Error, Equatable {
    case couldNotCreate(errno: Int32)
    case couldNotWrite(errno: Int32)
    case compressionFailed(status: Int32)
}

/// Writes a dump into its file in the snapshot as it arrives, compressed with gzip when asked, so a
/// dump of any size passes through without being held in memory.
final class DumpFileWriter: Sendable {
    /// zlib's own default, which it has no constant for.
    private static let memoryLevel: Int32 = 8
    /// Adding 16 to the window size makes zlib write a gzip header and trailer instead of its own.
    private static let gzipWindowBits = MAX_WBITS + 16
    private static let outputSize = 64 * 1024

    private struct State {
        let descriptor: Int32
        /// Nil when the dump is stored as it comes. zlib's stream points back at itself, so it can't move.
        let stream: UnsafeMutablePointer<z_stream>?
        let output: UnsafeMutableBufferPointer<Bytef>
        var summary = DumpFileSummary()
        var isClosed = false
    }

    private let state: Mutex<State>

    /// Refuses to replace anything at `url`, or to follow a link there.
    init(creating url: URL, compressed: Bool) throws {
        // Only Hive's user can read a dump, whatever the snapshot's other files allow.
        let descriptor = open(url.fileSystemPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw DumpFileError.couldNotCreate(errno: errno) }

        var stream: UnsafeMutablePointer<z_stream>?
        if compressed {
            let new = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
            new.initialize(to: z_stream())
            let status = deflateInit2_(
                new,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                Self.gzipWindowBits,
                Self.memoryLevel,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard status == Z_OK else {
                new.deallocate()
                close(descriptor)
                throw DumpFileError.compressionFailed(status: status)
            }
            stream = new
        }
        state = Mutex(State(descriptor: descriptor, stream: stream, output: .allocate(capacity: Self.outputSize)))
    }

    deinit {
        state.withLock { state in
            if !state.isClosed { close(state.descriptor) }
            if let stream = state.stream {
                deflateEnd(stream)
                stream.deallocate()
            }
            state.output.deallocate()
        }
    }

    func write(_ data: Data) throws {
        try state.withLock { state in
            state.summary.record(data)
            try data.withUnsafeBytes { bytes in
                guard let stream = state.stream else {
                    try Self.writeAll(bytes, to: state.descriptor)
                    state.summary.bytesStored += Int64(bytes.count)
                    return
                }
                stream.pointee.next_in = UnsafeMutablePointer(mutating: bytes.bindMemory(to: Bytef.self).baseAddress)
                stream.pointee.avail_in = uInt(bytes.count)
                try Self.compress(&state, flush: Z_NO_FLUSH)
            }
        }
    }

    /// Ends and closes the file, once the dump has finished.
    func finish() throws -> DumpFileSummary {
        try state.withLock { state in
            if let stream = state.stream {
                stream.pointee.next_in = nil
                stream.pointee.avail_in = 0
                try Self.compress(&state, flush: Z_FINISH)
            }
            state.isClosed = true
            guard close(state.descriptor) == 0 else { throw DumpFileError.couldNotWrite(errno: errno) }
            return state.summary
        }
    }

    /// Runs zlib until it has taken all its input, or with `Z_FINISH`, written its trailer.
    private static func compress(_ state: inout State, flush: Int32) throws {
        guard let stream = state.stream else { return }
        repeat {
            stream.pointee.next_out = state.output.baseAddress
            stream.pointee.avail_out = uInt(state.output.count)
            let status = deflate(stream, flush)
            // Z_BUF_ERROR only means there was nothing to do this time.
            guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                throw DumpFileError.compressionFailed(status: status)
            }
            let produced = state.output.count - Int(stream.pointee.avail_out)
            try writeAll(UnsafeRawBufferPointer(rebasing: UnsafeRawBufferPointer(state.output)[..<produced]), to: state.descriptor)
            state.summary.bytesStored += Int64(produced)
        } while stream.pointee.avail_out == 0
    }

    private static func writeAll(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
        guard var next = bytes.baseAddress else { return }
        var remaining = bytes.count
        while remaining > 0 {
            let written = Darwin.write(descriptor, next, remaining)
            if written < 0 {
                if errno == EINTR { continue }
                throw DumpFileError.couldNotWrite(errno: errno)
            }
            next += written
            remaining -= written
        }
    }
}
