import Darwin
import Foundation

/// SMAppService only says whether the daemon is approved, so whether it's running comes from the process list.
struct DaemonProcessFinder {
    let executable: URL

    func isRunning() -> Bool {
        let expectedPath = executable.resolvingSymlinksInPath().path(percentEncoded: false)
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return false }

        // Room for processes that start between the two calls.
        var processIDs = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = processIDs.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return false }

        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return processIDs.prefix(Int(count)).contains { processID in
            let length = proc_pidpath(processID, &path, UInt32(path.count))
            guard length > 0 else { return false }
            return String(bytes: path.prefix(Int(length)).map { UInt8(bitPattern: $0) }, encoding: .utf8) == expectedPath
        }
    }
}
