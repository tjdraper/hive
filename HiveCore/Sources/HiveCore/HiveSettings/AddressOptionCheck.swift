import Darwin
import Foundation
import HiveKit

/// Checks address options before they're saved and handed to new devices in pairing codes. Only the
/// form is checked: whether another device can reach Hive there is for that device to find out.
enum AddressOptionCheck {
    static let longestLabel = 63

    /// The options with each host in one written form. Throws `SettingsChangeError.refused` when any is no
    /// good, or two are the same.
    static func validated(_ options: [AddressOption]) throws -> [AddressOption] {
        guard options.count <= PairingCode.largestAddressCount else { throw SettingsChangeError.refused(.tooManyAddressOptions) }
        var checked: [AddressOption] = []
        for option in options {
            guard let host = host(option.host),
                  option.port.map(HiveSettingsWorkflow.anyPort.contains) ?? true
            else { throw SettingsChangeError.refused(.invalidAddressOption) }
            let normalized = AddressOption(host: host, port: option.port)
            guard !checked.contains(normalized) else { throw SettingsChangeError.refused(.invalidAddressOption) }
            checked.append(normalized)
        }
        return checked
    }

    /// An IP address another device could reach, or a DNS name, lowercased and without a trailing dot.
    static func host(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespaces).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }

        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 || inet_pton(AF_INET6, host, &ipv6) == 1 {
            return ListenAddress.reachable(host)
        }
        return isName(host) ? host : nil
    }

    private static func isName(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !host.isEmpty, host.utf8.count <= PairingCode.longestHost,
              labels.allSatisfy(isLabel),
              // A name ending in a number would be an IPv4 address written wrong, such as 300.1.1.1.
              labels.last?.allSatisfy(\.isNumber) == false,
              host != "localhost", !host.hasSuffix(".localhost")
        else { return false }
        return true
    }

    private static func isLabel(_ label: Substring) -> Bool {
        (1 ... longestLabel).contains(label.count)
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            && label.first != "-" && label.last != "-"
    }
}
