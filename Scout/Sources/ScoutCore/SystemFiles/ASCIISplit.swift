extension StringProtocol where SubSequence == Substring {
    /// The parts between each `separator`, without empty ones. The kernel's files are ASCII apart from
    /// names, so they're split on the byte: splitting by `Character` works out Unicode grapheme
    /// boundaries for every character, which took most of the time Scout spent reading them.
    func split(byte separator: Unicode.Scalar) -> [Substring] {
        let whole = self[...]
        let separator = UInt8(ascii: separator)
        var parts: [Substring] = []
        var start = whole.utf8.startIndex
        var index = start
        while index != whole.utf8.endIndex {
            if whole.utf8[index] == separator {
                if index != start { parts.append(Substring(whole.utf8[start..<index])) }
                start = whole.utf8.index(after: index)
            }
            index = whole.utf8.index(after: index)
        }
        if start != whole.utf8.endIndex { parts.append(Substring(whole.utf8[start...])) }
        return parts
    }

    var lines: [Substring] {
        split(byte: "\n")
    }
}
