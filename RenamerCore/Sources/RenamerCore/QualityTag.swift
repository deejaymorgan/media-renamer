import Foundation

/// Derives a short, human-readable *version label* from a release filename so
/// that two files which would otherwise land on the same destination (e.g. a
/// 1080p and a 2160p copy of the same movie) can be told apart.
///
/// This is NOT ported from the Python engine — the original only *detects*
/// duplicate targets and skips them. The label feeds the duplicate-resolve
/// panel, where it becomes a filename suffix: `Movie (Year) - 2160p Remux.mkv`.
/// Both versions stay in the same `Movie (Year)/` folder, which is how Plex and
/// Jellyfin group multiple versions of one title.
public enum QualityTag {

    /// (canonical display form, lowercased aliases). First hit in each group
    /// wins; at most one facet per group contributes to a label.
    private static let resolution: [(String, [String])] = [
        ("2160p", ["2160p", "4k", "uhd"]),
        ("1080p", ["1080p"]),
        ("1080i", ["1080i"]),
        ("720p",  ["720p"]),
        ("576p",  ["576p"]),
        ("480p",  ["480p"]),
    ]
    private static let source: [(String, [String])] = [
        ("Remux",  ["remux"]),
        ("BluRay", ["bluray", "blu-ray", "bdrip", "brrip"]),
        ("WEB-DL", ["web-dl", "webdl"]),
        ("WEBRip", ["webrip", "web"]),
        ("HDTV",   ["hdtv"]),
        ("DVDRip", ["dvdrip", "dvd", "dvd5", "dvd9"]),
    ]
    private static let dynamicRange: [(String, [String])] = [
        ("DV",     ["dv", "dovi"]),
        ("HDR10+", ["hdr10+"]),
        ("HDR",    ["hdr", "hdr10"]),
    ]
    private static let edition: [(String, [String])] = [
        ("Director's Cut", ["directors", "director's"]),
        ("Extended",       ["extended"]),
        ("Theatrical",     ["theatrical"]),
        ("Remastered",     ["remastered"]),
        ("Uncut",          ["uncut"]),
        ("Unrated",        ["unrated"]),
        ("IMAX",           ["imax"]),
        ("Criterion",      ["criterion"]),
    ]

    /// Lowercased tokens of a filename. Splits on `.`, `_`, and spaces but keeps
    /// hyphens and `+` *inside* tokens, so "web-dl", "blu-ray", and "hdr10+"
    /// survive intact to match their aliases.
    static func tokens(_ filename: String) -> Set<String> {
        let name = Str.splitext(filename).root
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return Set(name.split(separator: " ").map { $0.lowercased() })
    }

    /// A version label like `"2160p Remux DV"`, in priority order
    /// (resolution · source · dynamic range · edition). Empty when the filename
    /// carries none of these markers.
    public static func descriptor(_ filename: String) -> String {
        let toks = tokens(filename)
        func hit(_ group: [(String, [String])]) -> String? {
            group.first { _, aliases in aliases.contains { toks.contains($0) } }?.0
        }
        return [hit(resolution), hit(source), hit(dynamicRange), hit(edition)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Labels for a group of sources that share a destination, guaranteed
    /// distinct. Falls back to "Version" when a filename has no markers, and
    /// appends " (2)", " (3)", … when two labels would otherwise collide
    /// (e.g. genuine duplicates of identical quality). Input order is preserved.
    public static func distinctLabels(for sources: [URL]) -> [URL: String] {
        var used: [String: Int] = [:]
        var result: [URL: String] = [:]
        for url in sources {
            let base = descriptor(url.lastPathComponent)
            let label = base.isEmpty ? "Version" : base
            let n = (used[label] ?? 0) + 1
            used[label] = n
            result[url] = n == 1 ? label : "\(label) (\(n))"
        }
        return result
    }
}
