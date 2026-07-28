import Foundation

/// How a node's files are laid out under the chosen root.
///
/// The two modes produce **byte-identical filenames** — only the containing path
/// differs. `computeDestination` builds the name once and branches only on where
/// it is placed, so this is true by construction rather than by coincidence.
public enum OutputMode: String, Sendable, Equatable, CaseIterable {
    /// `Show/Season N/…` and `Movie (Year)/…` — the original behaviour.
    case organise
    /// Every file directly in the chosen root, with no folder tree.
    case renameOnly
}

/// A per-group or per-item setting: defer to the level above, or force a mode.
public enum ModeOverride: String, Sendable, Equatable, CaseIterable {
    case inherit
    case organise
    case renameOnly

    /// The mode this override forces, or nil when it defers upward.
    /// The single place `inherit` is turned into a decision.
    public var forced: OutputMode? {
        switch self {
        case .inherit:    return nil
        case .organise:   return .organise
        case .renameOnly: return .renameOnly
        }
    }
}

/// The three-level cascade. Nearest explicit setting wins: item → group → global.
///
/// The global level always has a value; the group ("all TV" / "all Movies") and
/// item levels are three-state, so an untouched level defers upward rather than
/// pinning a mode. The engine's default global is `.organise`, which keeps every
/// existing call site behaving exactly as before; the *product* default
/// (rename-only, per launch) is a UI decision and lives in the app.
public struct ModeCascade: Sendable, Equatable {
    public var global: OutputMode
    public var tv: ModeOverride
    public var movies: ModeOverride
    /// Per-item overrides, keyed by the node's source URL — the same key the
    /// title-edit and disambiguation layers already use.
    public var items: [URL: ModeOverride]

    public init(global: OutputMode = .organise,
                tv: ModeOverride = .inherit,
                movies: ModeOverride = .inherit,
                items: [URL: ModeOverride] = [:]) {
        self.global = global
        self.tv = tv
        self.movies = movies
        self.items = items
    }

    /// The effective mode for one node.
    public func mode(for source: URL, mediaType: MediaType) -> OutputMode {
        if let forced = items[source]?.forced { return forced }
        switch mediaType {
        case .tv:      if let f = tv.forced { return f }
        case .movie:   if let f = movies.forced { return f }
        case .unknown: break
        }
        return global
    }
}
