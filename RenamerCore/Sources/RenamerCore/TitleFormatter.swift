import Foundation

/// Title casing and normalisation. Ported from the Python engine's
/// `title_case`, `normalise_title`, and `find_preserved_stopwords`.
public enum TitleFormatter {

    /// Capitalise the first letter of each word, preserving known acronyms.
    /// Short connector words (articles, prepositions, conjunctions) stay
    /// lowercase when they sit between the first and last word of the title.
    ///
    /// `acronyms` maps an UPPERCASED word to its desired rendering
    /// (e.g. `["NASA": "NASA"]`); resolving that map is a UI concern.
    public static func titleCase(_ text: String, acronyms: [String: String] = [:]) -> String {
        let matches = Patterns.word.allMatches(text)
        if matches.isEmpty { return text }
        let lastIdx = matches.count - 1

        var out = ""
        var pos = text.startIndex
        for (i, m) in matches.enumerated() {
            guard let r = Range(m.range, in: text) else { continue }
            out += text[pos..<r.lowerBound]          // separator before this word
            let word = String(text[r])
            let isEdge = (i == 0 || i == lastIdx)
            out += capWord(word, isEdge: isEdge, acronyms: acronyms)
            pos = r.upperBound
        }
        out += text[pos...]                          // trailing separator
        return out
    }

    private static func capWord(
        _ word: String, isEdge: Bool, acronyms: [String: String]
    ) -> String {
        let upper = word.uppercased()
        if let mapped = acronyms[upper] { return mapped }
        if isEdge { return Str.capitalizeWord(word) }
        if Constants.titleLowercaseWords.contains(word.lowercased()) {
            // Mid-title stopword. If the source explicitly capitalised it
            // (e.g. release group's "Wicked.For.Good"), preserve that; if it
            // was lowercase, apply the title-case convention.
            if let first = word.first, first.isUppercase, word != word.uppercased() {
                return Str.capitalizeWord(word)
            }
            return word.lowercased()
        }
        return Str.capitalizeWord(word)
    }

    /// Dots → spaces, colon → `" - "` (illegal in macOS filenames), collapse
    /// whitespace, then title-case.
    public static func normalise(_ raw: String, acronyms: [String: String] = [:]) -> String {
        var title = raw.replacingOccurrences(of: ".", with: " ")
        title = title.replacingOccurrences(of: ":", with: " - ")
        title = Str.collapseSpaces(title)
        return titleCase(title, acronyms: acronyms)
    }

    /// Mid-title connector words carrying an explicit source capital (capital
    /// first letter, not all-caps). These survive the title-case pass intact,
    /// so they're worth flagging for the user to verify.
    public static func preservedStopwords(_ spaced: String) -> [String] {
        let matches = Patterns.word.allMatches(spaced)
        if matches.isEmpty { return [] }
        let lastIdx = matches.count - 1
        var flagged: [String] = []
        for (i, m) in matches.enumerated() {
            if i == 0 || i == lastIdx { continue }
            guard let r = Range(m.range, in: spaced) else { continue }
            let w = String(spaced[r])
            if Constants.titleLowercaseWords.contains(w.lowercased()),
               let first = w.first, first.isUppercase, w != w.uppercased() {
                flagged.append(w)
            }
        }
        return flagged
    }
}
