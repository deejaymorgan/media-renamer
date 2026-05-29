import Foundation

/// Reference data sets, ported verbatim from the original Python engine's
/// `data.py`. Pure data — no logic lives here.
public enum Constants {

    // MARK: File classes

    /// The only primary video container we restructure.
    public static let videoExtensions: Set<String> = [".mkv"]

    /// Subtitle sidecars renamed alongside their video.
    public static let subtitleExtensions: Set<String> =
        [".srt", ".sub", ".idx", ".ass", ".ssa", ".vtt"]

    /// Everything we keep when moving a title (video + subtitles).
    public static var sidecarExtensions: Set<String> {
        videoExtensions.union(subtitleExtensions)
    }

    // MARK: Title casing

    /// Connector words kept lowercase when they sit *between* the first and last
    /// word of a title (Chicago/AP convention): articles, short prepositions,
    /// coordinating conjunctions.
    static let titleLowercaseWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "en", "for",
        "if", "in", "of", "on", "or", "the", "to", "via", "vs",
    ]

    // MARK: Year detection

    /// PTP/scene metadata tokens that confirm a 4-digit number is the *release
    /// year* rather than a year-shaped part of the title.
    static let ptpMetadataTokens: Set<String> = [
        "480p", "576p", "720p", "1080p", "1080i", "2160p", "4k",
        "bluray", "blu-ray", "bdrip", "brrip", "dvdrip", "dvd5", "dvd9",
        "web-dl", "webrip", "web", "hdtv", "hddvd", "hd-dvd", "vhsrip",
        "tvrip", "uhd", "remux",
        "x264", "x265", "h.264", "h264", "h.265", "h265", "hevc", "avc",
        "xvid", "divx", "vc-1", "mpeg-2", "mpeg2",
        "aac", "ac3", "eac3", "dts", "dts-hd", "truehd", "atmos", "flac",
        "pcm", "mp3", "opus", "dd5.1", "ddp5.1", "5.1", "7.1", "2.0",
        "hdr", "hdr10", "hdr10+", "dv", "dovi", "sdr",
        "directors", "director's", "extended", "unrated", "uncut",
        "theatrical", "remastered", "imax", "criterion", "repack",
        "proper", "internal", "limited", "3d", "cut",
        "amzn", "nf", "dsnp", "hmax", "atvp", "hulu", "stan",
    ]

    // MARK: Subtitle languages

    /// ISO 639-1/2 subtitle language codes worth preserving on rename.
    static let languageCodes: Set<String> = [
        "en", "eng", "english",
        "fr", "fre", "fra", "french",
        "es", "esp", "spa", "spanish",
        "de", "ger", "deu", "german",
        "it", "ita", "italian",
        "pt", "por", "portuguese", "pt-br", "pob",
        "nl", "dut", "nld", "dutch",
        "ja", "jpn", "japanese",
        "ko", "kor", "korean",
        "zh", "chi", "zho", "chinese",
        "ru", "rus", "russian",
        "ar", "ara", "arabic",
        "hi", "hin", "hindi",
        "pl", "pol", "polish",
        "sv", "swe", "swedish",
        "no", "nor", "norwegian",
        "da", "dan", "danish",
        "fi", "fin", "finnish",
        "cs", "cze", "ces", "czech",
        "tr", "tur", "turkish",
        "el", "gre", "ell", "greek",
        "he", "heb", "hebrew",
        "th", "tha", "thai",
        "vi", "vie", "vietnamese",
        "uk", "ukr", "ukrainian",
        "hu", "hun", "hungarian",
        "ro", "ron", "rum", "romanian",
    ]

    // MARK: Folder handling

    /// Top-level library-category folders that are never descended into or
    /// restructured (so running on a parent like ~/Media is safe).
    public static let ignoredFolderNames: Set<String> = ["movies", "music", "tv"]

    /// Case-insensitive name fragments that mark junk regardless of extension —
    /// substring forms of data.py's `sample`, `screens?`, `proof`, `thumbs?`
    /// regexes, so "screen"/"screens"/"screenshots" and "thumb"/"thumbs" match.
    static let junkNamePatterns: [String] = ["sample", "screen", "proof", "thumb"]
}
