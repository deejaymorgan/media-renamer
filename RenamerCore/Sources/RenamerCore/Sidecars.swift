import Foundation

/// Subtitle sidecar handling. Ported from `detect_language_suffix` /
/// `new_sidecar_name`.
public enum Sidecars {

    /// The language sub-extension (with leading dot) if the last dot-token
    /// before the real extension is a known language code, else "".
    /// `"Movie.2010.eng.srt" -> ".eng"`, `"Movie.2010.srt" -> ""`.
    public static func languageSuffix(_ filename: String) -> String {
        let base = Str.splitext(filename).root
        guard let dot = base.lastIndex(of: ".") else { return "" }
        let tail = String(base[base.index(after: dot)...]).lowercased()
        return Constants.languageCodes.contains(tail) ? ".\(tail)" : ""
    }

    /// The target filename for a sidecar, preserving any language suffix.
    /// `newName(targetStem: "Movie (2010)", source: "Movie.2010.eng.srt")
    /// -> "Movie (2010).eng.srt"`.
    public static func newName(targetStem: String, source: String) -> String {
        let ext = Str.splitext(source).ext
        return "\(targetStem)\(languageSuffix(source))\(ext)"
    }

    /// Map each video to the sidecars that belong to it. A sidecar belongs to
    /// the video whose stem is the longest prefix of the sidecar's stem (after
    /// stripping a trailing language code); falls back to the only/first video.
    /// Ported from `group_sidecars`.
    public static func group(videos: [URL], sidecars: [URL]) -> [URL: [URL]] {
        if sidecars.isEmpty {
            return Dictionary(uniqueKeysWithValues: videos.map { ($0, [URL]()) })
        }
        if videos.count == 1 {
            return [videos[0]: sidecars]
        }
        var out: [URL: [URL]] = Dictionary(uniqueKeysWithValues: videos.map { ($0, [URL]()) })
        let videoStems = videos.map { ($0, Str.splitext($0.lastPathComponent).root) }
        for s in sidecars {
            var stem = Str.splitext(s.lastPathComponent).root
            let lang = languageSuffix(s.lastPathComponent)
            if !lang.isEmpty { stem = String(stem.dropLast(lang.count)) }
            var best: URL?
            var bestLen = -1
            for (v, vStem) in videoStems where stem.hasPrefix(vStem) && vStem.count > bestLen {
                best = v
                bestLen = vStem.count
            }
            out[best ?? videos[0], default: []].append(s)
        }
        return out
    }
}
