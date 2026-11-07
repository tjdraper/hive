import Foundation
import os

/// Runs an executable to completion, collecting what it writes, and stops it when the task running it
/// is cancelled.
struct ChildProcess: Sendable {
    enum Event: Sendable, Equatable {
        case standardOutput(Data)
        case standardError(Data)
        /// Always the last event, and only sent once both outputs have been read to the end.
        case exited(status: Int32)
    }

    struct Result: Sendable, Equatable {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
    }

    enum Failure: Error {
        case couldNotStart(any Error)
    }

    /// `ssh` and `rsync` clean up on SIGTERM, so they get the chance first.
    private static let terminationGracePeriod: DispatchTimeInterval = .seconds(2)

    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    /// Written to the process's standard input, which is then closed.
    var input: Data?
    /// Takes standard output as it arrives instead of collecting it, so output of any size passes
    /// through without being held in memory. It's called once at a time, and the process waits on a
    /// full pipe meanwhile, so slow writing slows the process rather than filling memory. Throwing stops
    /// the process, and running it then throws that error.
    var standardOutputHandler: (@Sendable (Data) throws -> Void)?

    func run() async throws -> Result {
        var standardOutput = Data()
        var standardError = Data()
        for try await event in stream() {
            switch event {
            case .standardOutput(let data):
                standardOutput.append(data)
            case .standardError(let data):
                standardError.append(data)
            case .exited(let status):
                return Result(status: status, standardOutput: standardOutput, standardError: standardError)
            }
        }
        // The stream only ends without an exit, or an error from the output handler, when the task was cancelled.
        throw CancellationError()
    }

    /// Cancelling the task that iterates the stream, or dropping the stream, stops the process.
    func stream() -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let standardInput = input.map { _ in Pipe() }
            let standardOutput = Pipe()
            let standardError = Pipe()

            // A process can exit before its output has been read, so the exit is only reported once
            // the process has ended and both pipes have reached end of file.
            let finished = DispatchGroup()
            finished.enter()
            let exitStatus = OSAllocatedUnfairLock<Int32>(initialState: 0)
            let handlerFailure = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)

            let process: SpawnedProcess
            do {
                process = try spawn(standardInput: standardInput, standardOutput: standardOutput, standardError: standardError) { status in
                    exitStatus.withLock { $0 = status }
                    finished.leave()
                }
            } catch {
                continuation.finish(throwing: Failure.couldNotStart(error))
                return
            }

            if let standardInput, let input {
                Self.write(input, to: standardInput)
            }

            finished.enter()
            if let handler = standardOutputHandler {
                Self.forward(standardOutput, then: finished, receive: Self.handing(to: handler, failure: handlerFailure, stopping: process))
            } else {
                Self.forward(standardOutput, then: finished) { continuation.yield(.standardOutput($0)) }
            }
            finished.enter()
            Self.forward(standardError, then: finished) { continuation.yield(.standardError($0)) }

            finished.notify(queue: .global()) {
                if let error = handlerFailure.withLock({ $0 }) {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.yield(.exited(status: exitStatus.withLock { $0 }))
                continuation.finish()
            }

            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                // Something the process started can hold the pipes open after it is gone, and
                // nothing is listening any more.
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                Self.stop(process)
            }
        }
    }

    /// Starts the process with the pipes' child ends, then closes them here.
    private func spawn(
        standardInput: Pipe?,
        standardOutput: Pipe,
        standardError: Pipe,
        exited: @escaping @Sendable (Int32) -> Void
    ) throws -> SpawnedProcess {
        let process = try SpawnedProcess(
            executable: executableURL,
            arguments: arguments,
            environment: environment,
            standardInput: standardInput?.fileHandleForReading.fileDescriptor ?? FileHandle.nullDevice.fileDescriptor,
            standardOutput: standardOutput.fileHandleForWriting.fileDescriptor,
            standardError: standardError.fileHandleForWriting.fileDescriptor,
            exited: exited
        )
        // Only the child may hold these ends open, or the pipes never reach end of file.
        try? standardInput?.fileHandleForReading.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
        return process
    }

    /// Passes output to `handler` until it throws, then records why, stops the process, and drops the
    /// rest while it ends.
    private static func handing(
        to handler: @escaping @Sendable (Data) throws -> Void,
        failure: OSAllocatedUnfairLock<(any Error)?>,
        stopping process: SpawnedProcess
    ) -> @Sendable (Data) -> Void {
        { data in
            guard failure.withLock({ $0 == nil }) else { return }
            do {
                try handler(data)
            } catch {
                failure.withLock { $0 = error }
                stop(process)
            }
        }
    }

    /// `receive` is called on the handle's own queue, one call at a time.
    private static func forward(_ pipe: Pipe, then finished: DispatchGroup, receive: @escaping @Sendable (Data) -> Void) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                finished.leave()
                return
            }
            receive(data)
        }
    }

    /// Away from the caller, since a process can fill its output pipe before it has read all its
    /// input, and would wait on a write here that waits on it.
    private static func write(_ input: Data, to pipe: Pipe) {
        let handle = pipe.fileHandleForWriting
        // Writing to a pipe whose reader has gone raises SIGPIPE, which would end the daemon.
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global().async {
            // A process that exits without reading everything closes the pipe, which is no error here.
            try? handle.write(contentsOf: input)
            try? handle.close()
        }
    }

    static func stop(_ process: SpawnedProcess) {
        guard process.isRunning else { return }
        process.signal(SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + terminationGracePeriod) {
            process.signal(SIGKILL)
        }
    }
}
