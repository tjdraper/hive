import Foundation

/// The commands that change Hive's line in a server's `~/.ssh/authorized_keys` while rotating its key.
/// Each runs as a POSIX `sh` script whatever the account's login shell, with the lines passed as
/// arguments rather than written into the script. Only the file `sshd` reads by default is changed.
enum AuthorizedKeysScript {
    /// The file's lines, as they are.
    static var read: String {
        command(#"cat -- "$HOME/.ssh/authorized_keys""#, arguments: [])
    }

    /// Adds `line` at the end unless it's there already, starting a new line first when the file's last
    /// one has no end. Exits 0 only when the line is in the file.
    static func add(_ line: String) -> String {
        command(addScript, arguments: [line])
    }

    /// Removes exactly `lines`, and only while `kept` is in the file. The file is written beside itself
    /// with its own mode and moved into place, so `sshd` never reads it half written. Exits 0 only once
    /// it's in place.
    static func remove(_ lines: [String], keeping kept: String) -> String {
        command(removeScript, arguments: [kept] + lines)
    }

    private static let addScript = #"""
    f="$HOME/.ssh/authorized_keys"
    [ -f "$f" ] && [ ! -L "$f" ] || exit 3
    if ! grep -q -x -F -e "$1" "$f"; then
        n=$(tail -c 1 "$f" | wc -l)
        if [ -s "$f" ] && [ $((n)) -eq 0 ]; then printf '\n' >> "$f" || exit 4; fi
        printf '%s\n' "$1" >> "$f" || exit 4
    fi
    grep -q -x -F -e "$1" "$f"
    """#

    private static let removeScript = #"""
    f="$HOME/.ssh/authorized_keys"
    t="$f.hive-rotation"
    [ -f "$f" ] && [ ! -L "$f" ] || exit 3
    kept="$1"
    shift
    grep -q -x -F -e "$kept" "$f" || exit 4
    n=$#
    for line do set -- "$@" -e "$line"; done
    shift "$n"
    rm -f "$t"
    cp -p "$f" "$t" || exit 5
    grep -v -x -F "$@" "$f" > "$t"
    [ $? -le 1 ] && grep -q -x -F -e "$kept" "$t" || { rm -f "$t"; exit 5; }
    mv -f "$t" "$f" || { rm -f "$t"; exit 5; }
    """#

    /// `sh` fills `$0`, so the arguments start at `$1`.
    private static func command(_ script: String, arguments: [String]) -> String {
        RemoteCommandLine.line(["sh", "-c", script, "sh"] + arguments)
    }
}
