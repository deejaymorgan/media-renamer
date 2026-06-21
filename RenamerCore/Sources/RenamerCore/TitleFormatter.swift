import Foundation

/// Title casing and normalisation. Ported from the Python engine's
/// `title_case`, `normalise_title`, and `find_preserved_stopwords`.
public enum TitleFormatter {

    /// Capitalise the first letter of each word, preserving known acronyms.
    /// Short connector words (articles, prepositions, conjunctions) stay
    /// lowercase when they sit between the first and last word of the title.
    /// A contraction or possessive tail keeps its lowercase letter
    /// (`Don't`, `Ocean's`, `BBC's`) — the word regex splits on the apostrophe,
    /// so the tail is re-joined by `isContraction` rather than re-capitalised.
    /// The one casualty is leading-particle names: `O'Brien` becomes `O'brien`,
    /// because `Str.capitalizeWord` (Python `str.capitalize` semantics)
    /// lowercases everything after the first letter regardless.
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
            let cont = isContraction(in: text, tokenStart: r.lowerBound)
            out += capWord(word, isEdge: isEdge, isContinuation: cont, acronyms: acronyms)
            pos = r.upperBound
        }
        out += text[pos...]                          // trailing separator
        return out
    }

    /// True when the token starting at `tokenStart` is the tail of a contraction
    /// or possessive — immediately preceded by an apostrophe that itself follows
    /// a letter (`Don['t]`, `Ocean['s]`). Such a fragment is a word continuation,
    /// not a new word, so it must not be re-capitalised. Both straight (U+0027)
    /// and curly (U+2019) apostrophes count. The lookback walks Unicode
    /// `Character`s, so it stays correct even though the word regex is ASCII-only
    /// (e.g. the letter before the apostrophe in `Beyoncé's`).
    private static func isContraction(in text: String, tokenStart: String.Index) -> Bool {
        guard tokenStart > text.startIndex else { return false }
        let apIdx = text.index(before: tokenStart)
        guard text[apIdx] == "'" || text[apIdx] == "\u{2019}" else { return false }
        guard apIdx > text.startIndex else { return false }
        return text[text.index(before: apIdx)].isLetter
    }

    private static func capWord(
        _ word: String, isEdge: Bool, isContinuation: Bool, acronyms: [String: String]
    ) -> String {
        // A contraction/possessive tail (`Don['t]`, `BBC['s]`) is a word
        // continuation, not a standalone word: lowercase it, and never treat it
        // as an acronym or stopword. Checked before the acronym lookup so the
        // "s" in "BBC's" is not surfaced as its own acronym chip.
        if isContinuation { return word.lowercased() }
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
