import Foundation

/// Classification and parsing of media filenames. Ported from the Python
/// engine's `classify`, `find_release_year`, `parse_tv`, and `parse_movie`.
///
/// All entry points take a *filename* (not a path) and strip the extension
/// themselves, mirroring the original.
public enum MediaParser {

    /// Classify a filename as TV (has an episode code), movie (has a release
    /// year), or unknown.
    public static func classify(_ filename: String) -> MediaType {
        let name = Str.splitext(filename).root
        if Patterns.episode.hasMatch(name) { return .tv }
        if releaseYear(name) != nil { return .movie }
        return .unknown
    }

    /// Locate the release-year span within `name` (the filename WITHOUT
    /// extension). Precedence:
    ///   1. canonical `(YYYY)` — always wins;
    ///   2. rightmost scene-style `.YYYY.<known metadata token>`;
    ///   3. fallback: rightmost year not at position 0.
    public static func releaseYear(_ name: String) -> Range<String.Index>? {
        let candidates = Patterns.year.allMatches(name)
            .compactMap { Range($0.range, in: name) }
        if candidates.isEmpty { return nil }

        // 1) Canonical (YYYY)
        for r in candidates {
            let before: Character? = r.lowerBound > name.startIndex
                ? name[name.index(before: r.lowerBound)] : nil
            let after: Character? = r.upperBound < name.endIndex
                ? name[r.upperBound] : nil
            if before == "(" && after == ")" { return r }
        }

        // 2) Scene form: rightmost `.YYYY.<known token>`
        var chosen: Range<String.Index>?
        for r in candidates {
            if r.lowerBound == name.startIndex { continue }
            if name[name.index(before: r.lowerBound)] != "." { continue }
            let tail = name[r.upperBound...]
            guard tail.first == "." else { continue }
            let nextToken = tail.dropFirst().prefix { $0 != "." }.lowercased()
            if Constants.ptpMetadataTokens.contains(nextToken) { chosen = r }
        }
        if let chosen { return chosen }

        // 3) Fallback: rightmost year not at position 0
        for r in candidates.reversed() where r.lowerBound != name.startIndex {
            return r
        }
        return nil
    }

    /// Parse a TV filename, or nil if it has no episode code.
    public static func tv(_ filename: String, acronyms: [String: String] = [:]) -> MediaParse? {
        let name = Str.splitext(filename).root
        guard let m = Patterns.episode.firstMatch(name),
              let matchRange = Range(m.range, in: name),
              let codeStr = groupString(m, 1, in: name),
              let seasonStr = groupString(m, 2, in: name),
              let season = Int(seasonStr)
        else { return nil }

        let titleRaw = String(name[..<matchRange.lowerBound])
        let preserved = TitleFormatter.preservedStopwords(
            titleRaw.replacingOccurrences(of: ".", with: " "))
        let normalised = TitleFormatter.normalise(titleRaw, acronyms: acronyms)
        return MediaParse(
            title: normalised.isEmpty ? "Unknown" : normalised,
            preservedStopwords: preserved,
            episodeCode: codeStr.uppercased(),
            season: season
        )
    }

    /// Parse a movie filename, or nil if no release year is found.
    public static func movie(_ filename: String, acronyms: [String: String] = [:]) -> MediaParse? {
        let name = Str.splitext(filename).root
        guard let span = releaseYear(name) else { return nil }
        let year = String(name[span])

        // Strip the scene-style trailing '.', canonical-style ' (', or both.
        var titleRaw = String(name[..<span.lowerBound])
        titleRaw = Str.rstrip(titleRaw, [" ", "("])
        titleRaw = Str.rstrip(titleRaw, ["."])
        var title = Str.collapseSpaces(titleRaw.replacingOccurrences(of: ".", with: " "))

        // AKA: discard the original-language left side, keep the English right.
        if let aka = Patterns.aka.firstMatch(title),
           let r = Range(aka.range, in: title) {
            title = String(title[r.upperBound...].drop(while: { $0 == " " }))
        }

        let preserved = TitleFormatter.preservedStopwords(title)
        let normalised = TitleFormatter.normalise(title, acronyms: acronyms)
        let finalTitle = normalised.isEmpty ? "Unknown" : normalised
        return MediaParse(title: "\(finalTitle) (\(year))", preservedStopwords: preserved)
    }

    /// The portion of a filename before its episode code (TV) or year (movie),
    /// used to scan for all-caps words. nil if neither is present.
    static func titlePortion(_ filename: String) -> String? {
        let name = Str.splitext(filename).root
        if let m = Patterns.episode.firstMatch(name), let r = Range(m.range, in: name) {
            return String(name[..<r.lowerBound])
        }
        if let span = releaseYear(name) {
            return String(name[..<span.lowerBound])
        }
        return nil
    }

    /// Unique all-caps words (≥2 letters) across the title portions of these
    /// filenames — the candidates for acronym keep/Title decisions. Movie titles
    /// drop the discarded left-of-AKA part. Ported from `collect_all_caps_words`.
    public static func collectAllCapsWords(_ filenames: [String]) -> [String] {
        var words = Set<String>()
        for filename in filenames {
            guard let raw = titlePortion(filename) else { continue }
            var title = raw.replacingOccurrences(of: ".", with: " ")
            if classify(filename) == .movie,
               let aka = Patterns.aka.firstMatch(title),
               let r = Range(aka.range, in: title) {
                title = String(title[r.upperBound...])
            }
            for m in Patterns.word.allMatches(title) {
                guard let r = Range(m.range, in: title) else { continue }
                let w = String(title[r])
                if w.count >= 2 && w == w.uppercased() { words.insert(w) }
            }
        }
        return words.sorted()
    }
}
