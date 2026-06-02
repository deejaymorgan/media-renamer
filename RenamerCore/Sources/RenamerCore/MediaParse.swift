import Foundation

/// What a filename was recognised as.
public enum MediaType: String, Sendable, Equatable {
    case tv
    case movie
    case unknown
}

/// The result of parsing a single filename.
///
/// For movies, `title` already includes the year, e.g. `"Inception (2010)"`.
/// For TV, `title` is the show name and `episodeCode`/`season` are populated.
public struct MediaParse: Equatable, Sendable {
    /// Movies: `"Title (YYYY)"`. TV: the show name.
    public var title: String

    /// Mid-title connector words that kept an explicit source capital
    /// (e.g. the "For" in "Wicked For Good") — surfaced so the user can
    /// double-check the real title.
    public var preservedStopwords: [String]

    /// TV only — normalised episode code, e.g. `"S01E01"`.
    public var episodeCode: String?

    /// TV only — season number (supports 4-digit year seasons like 2024).
    public var season: Int?

    /// A version label this file already carries in our own output convention
    /// (`Title (Year) - <label>.ext`), e.g. "2160p Remux". Preserved so that
    /// re-scanning an already-resolved file reproduces its current name rather
    /// than re-flagging a duplicate. Empty for ordinary inputs.
    public var versionLabel: String

    public init(
        title: String,
        preservedStopwords: [String] = [],
        episodeCode: String? = nil,
        season: Int? = nil,
        versionLabel: String = ""
    ) {
        self.title = title
        self.preservedStopwords = preservedStopwords
        self.episodeCode = episodeCode
        self.season = season
        self.versionLabel = versionLabel
    }
}
