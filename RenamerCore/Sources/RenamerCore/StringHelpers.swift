import Foundation

/// Small helpers that reproduce specific Python string behaviours the engine
/// relies on, so the ported rules behave identically to the original.
enum Str {

    /// Mirrors Python's `str.capitalize()`: first character upper, rest lower.
    /// `"mATRIX" -> "Matrix"`, `"A" -> "A"`, `"" -> ""`.
    static func capitalizeWord(_ w: String) -> String {
        guard let first = w.first else { return w }
        return first.uppercased() + w.dropFirst().lowercased()
    }

    /// Mirrors Python's `str.rstrip(chars)`: remove trailing characters that are
    /// in `chars` (a *set*, not a suffix). `rstrip("Inception (", [" ", "("])
    /// -> "Inception"`.
    static func rstrip(_ s: String, _ chars: Set<Character>) -> String {
        var end = s.endIndex
        while end > s.startIndex {
            let prev = s.index(before: end)
            if chars.contains(s[prev]) { end = prev } else { break }
        }
        return String(s[..<end])
    }

    /// Mirrors Python's `os.path.splitext`: split at the last dot, except a
    /// leading dot (hidden file) is not an extension.
    /// `"a.mkv" -> ("a", ".mkv")`, `".DS_Store" -> (".DS_Store", "")`.
    static func splitext(_ name: String) -> (root: String, ext: String) {
        guard let dot = name.lastIndex(of: ".") else { return (name, "") }
        let leadingDots = name.prefix { $0 == "." }.count
        let dotOffset = name.distance(from: name.startIndex, to: dot)
        if dotOffset < leadingDots { return (name, "") }
        return (String(name[..<dot]), String(name[dot...]))
    }

    /// Collapse runs of spaces to a single space and trim the ends.
    /// `"  a   b " -> "a b"`. Matches Python `re.sub(r" +", " ", s).strip()`
    /// for space-delimited input.
    static func collapseSpaces(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
