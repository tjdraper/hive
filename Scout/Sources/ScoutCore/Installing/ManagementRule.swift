/// The name of the user Hive signs in to the server as, checked before it goes into a `sudo` or `doas`
/// rule, so it can't add a rule of its own.
struct SSHUserName: Equatable, Sendable {
    /// `useradd`'s limit on most distributions.
    static let longest = 32
    /// Words that start a line of their own in a `sudoers` file.
    private static let sudoKeywords: Set = ["Defaults", "Host_Alias", "User_Alias", "Runas_Alias", "Cmnd_Alias", "Cmd_Alias"]

    let text: String

    /// Nil for anything outside POSIX's portable user name pattern (letters, digits, `.`, `_` and `-`,
    /// not starting with `-`), or that `sudo` would read as an alias, such as `ALL`, or a keyword.
    init?(_ text: String) {
        let bytes = Array(text.utf8)
        guard let first = bytes.first, bytes.count <= Self.longest, first != UInt8(ascii: "-"),
              bytes.allSatisfy(Self.isPortable)
        else { return nil }
        // An alias is an upper-case letter followed by upper-case letters, digits and underscores.
        let isAlias = (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(first)
            && bytes.allSatisfy { Self.isUpperCase($0) || Self.isDigit($0) || $0 == UInt8(ascii: "_") }
        guard !isAlias, !Self.sudoKeywords.contains(text) else { return nil }
        self.text = text
    }

    private static func isPortable(_ byte: UInt8) -> Bool {
        isUpperCase(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || isDigit(byte)
            || [UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "-")].contains(byte)
    }

    private static func isUpperCase(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}

/// Lets Hive's SSH user run Scout's management command as root, with no other arguments, and nothing
/// else: through `sudo`, or `doas` on a server without it, such as Alpine.
enum ManagementRule: Equatable {
    case sudo
    case doas

    func path(in layout: InstallLayout) -> String {
        switch self {
        case .sudo: layout.sudoRule
        case .doas: layout.doasRule
        }
    }

    /// `sudo` matches the arguments exactly when a rule gives any. Hive's key is added with `restrict`,
    /// so its commands have no terminal.
    func text(for user: SSHUserName, binary: String) -> String {
        switch self {
        case .sudo:
            """
            # Written by hive-scout install --ssh-user, and removed by hive-scout uninstall.
            Defaults!\(binary) !requiretty
            \(user.text) ALL=(root) NOPASSWD: \(binary) manage

            """
        case .doas:
            """
            # Written by hive-scout install --ssh-user, and removed by hive-scout uninstall.
            permit nopass \(user.text) as root cmd \(binary) args manage

            """
        }
    }
}
