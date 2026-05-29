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
}
