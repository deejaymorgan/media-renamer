import Foundation

/// Compiled regular expressions, ported from `data.py`.
///
/// We use `NSRegularExpression` (ICU) for byte-for-byte parity with Python's
/// `re` on these patterns — notably the year look-around `(?<!\d)…(?!\d)`.
/// `NSRegularExpression` is `Sendable`, so sharing the compiled objects as
/// shared constants is safe under Swift 6 concurrency.
enum Patterns {
    /// TV episode codes: S01E01, S01E01E02, S01E01-E02, S2024E01 — any casing.
    static let episode = try! NSRegularExpression(
        pattern: #"(S(\d{2,4})E(\d{2})(?:E\d{2}|-E\d{2})?)"#,
        options: [.caseInsensitive]
    )

    /// A 4-digit 19xx/20xx not adjacent to another digit.
    static let year = try! NSRegularExpression(
        pattern: #"(?<!\d)(19\d{2}|20\d{2})(?!\d)"#
    )

    /// A run of ASCII letters (one "word" for title casing).
    static let word = try! NSRegularExpression(
        pattern: #"[A-Za-z]+"#
    )

    /// The "AKA" separator in movie titles (keep the right-hand side).
    static let aka = try! NSRegularExpression(
        pattern: #"\bAKA\b"#,
        options: [.caseInsensitive]
    )
}

extension NSRegularExpression {
    /// First match over the whole string, or nil.
    func firstMatch(_ s: String) -> NSTextCheckingResult? {
        firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s))
    }

    /// All matches over the whole string, left to right.
    func allMatches(_ s: String) -> [NSTextCheckingResult] {
        matches(in: s, options: [], range: NSRange(s.startIndex..., in: s))
    }

    /// Whether the pattern occurs anywhere in `s`.
    func hasMatch(_ s: String) -> Bool { firstMatch(s) != nil }
}

/// The Swift string range of capture group `i` in a match, or nil if unmatched.
func groupRange(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> Range<String.Index>? {
    let r = m.range(at: i)
    guard r.location != NSNotFound else { return nil }
    return Range(r, in: s)
}

/// The captured substring for group `i`, or nil if unmatched.
func groupString(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
    guard let r = groupRange(m, i, in: s) else { return nil }
    return String(s[r])
}
