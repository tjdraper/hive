/// The parts of `/etc/os-release` Scout reports. The format is shell-style `KEY=value` lines, with
/// values optionally quoted (https://www.freedesktop.org/software/systemd/man/latest/os-release.html).
struct OSRelease: Equatable {
    var prettyName: String?
    var name: String?
    var version: String?

    /// `PRETTY_NAME` where it's set, as the specification asks, otherwise the name and version.
    var distribution: String? {
        if let prettyName { return prettyName }
        guard let name else { return nil }
        return [name, version].compactMap(\.self).joined(separator: " ")
    }

    init(parsing text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingWhitespace()
            let value = Self.unquoted(line[line.index(after: equals)...].trimmingWhitespace())
            switch key {
            case "PRETTY_NAME": prettyName = value
            case "NAME": name = value
            case "VERSION": version = value
            default: continue
            }
        }
    }

    private static func unquoted(_ value: Substring) -> String? {
        var value = value
        if let first = value.first, first == "\"" || first == "'", value.count >= 2, value.last == first {
            value = value.dropFirst().dropLast()
        }
        var result = ""
        var escaping = false
        for character in value {
            if escaping || character != "\\" {
                result.append(character)
                escaping = false
            } else {
                escaping = true
            }
        }
        return result.isEmpty ? nil : result
    }
}

extension Substring {
    func trimmingWhitespace() -> Substring {
        let start = firstIndex { !$0.isWhitespace } ?? endIndex
        let end = self[start...].lastIndex { !$0.isWhitespace }.map(index(after:)) ?? start
        return self[start..<end]
    }
}
