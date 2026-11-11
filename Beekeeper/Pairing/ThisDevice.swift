import Foundation
#if os(iOS)
import UIKit
#endif

/// What this device is called when it pairs, which the Hive's device list shows.
enum ThisDevice {
    static var name: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }
}
