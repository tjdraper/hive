#if os(macOS)
import Foundation

/// Where the running copy of Beekeeper really is.
enum AppLocation: Equatable {
    case inPlace(URL)
    /// macOS runs a downloaded app opened where it was unpacked from a randomized, read-only path
    /// (App Translocation). The original is nil when it couldn't be found.
    case translocated(original: URL?)
}

/// Security.framework exports the functions that find a translocated app's original, but leaves them out of
/// its headers. They're looked up at run time, so Beekeeper still runs, and only loses the original's
/// location, if a later macOS drops them. LetsMove (github.com/potionfactory/LetsMove) uses the same two.
enum TranslocationResolver {
    private typealias IsTranslocatedFunction = @convention(c) (
        CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> DarwinBoolean
    private typealias OriginalPathFunction = @convention(c) (
        CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> Unmanaged<CFURL>?

    static func locate(_ bundleURL: URL) -> AppLocation {
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isTranslocatedSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL")
        else {
            return bundleURL.path.contains("/AppTranslocation/") ? .translocated(original: nil) : .inPlace(bundleURL)
        }

        let isTranslocatedURL = unsafeBitCast(isTranslocatedSymbol, to: IsTranslocatedFunction.self)
        var isTranslocated = false
        guard isTranslocatedURL(bundleURL as CFURL, &isTranslocated, nil).boolValue, isTranslocated else {
            return .inPlace(bundleURL)
        }

        guard let originalPathSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else {
            return .translocated(original: nil)
        }
        let originalPath = unsafeBitCast(originalPathSymbol, to: OriginalPathFunction.self)
        let original = originalPath(bundleURL as CFURL, nil)?.takeRetainedValue() as URL?
        return .translocated(original: original)
    }
}
#endif
