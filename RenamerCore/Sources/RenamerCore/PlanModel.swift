import Foundation

/// A single filesystem operation in a plan.
public enum Operation: Equatable, Sendable {
    /// Move (rename or relocate) a file from one URL to another.
    case move(from: URL, to: URL)
    /// Remove the source directory if it is empty after its contents moved out.
    case removeEmptyDirectory(URL)

    public var isMove: Bool {
        if case .move = self { return true } else { return false }
    }
}

/// What will happen to a top-level node.
public enum PlanStatus: String, Sendable, Equatable {
    case rename
    case unchanged
    case skip
}

/// A before→after display pair. Paths are relative to the input root.
public struct PreviewPair: Equatable, Sendable {
    public let old: String
    public let new: String
    public init(old: String, new: String) {
        self.old = old
        self.new = new
    }
}

/// One output file in a rename node — carries just enough to recompute its
/// destination when the user edits the title/year, without re-scanning or
/// re-parsing. Season/episode code stay fixed; only the title (and movie year)
/// are user-editable.
public struct RenameUnit: Equatable, Sendable {
    public let source: URL
    public let episodeCode: String?    // TV video & its sidecars; nil for movies
    public let season: Int?            // TV
    public let languageSuffix: String  // sidecar language (".eng"), else ""
    public let ext: String             // ".mkv", ".srt", …
    /// Version label appended as " - <suffix>" before the language/extension to
    /// resolve a duplicate target (e.g. "2160p Remux"). Empty in the normal case.
    public var disambiguationSuffix: String

    public init(source: URL, episodeCode: String?, season: Int?,
                languageSuffix: String, ext: String,
                disambiguationSuffix: String = "") {
        self.source = source
        self.episodeCode = episodeCode
        self.season = season
        self.languageSuffix = languageSuffix
        self.ext = ext
        self.disambiguationSuffix = disambiguationSuffix
    }
}

/// The plan for a single top-level node (a loose file or a subfolder).
/// Ported from the Python `NodePlan`.
public struct NodePlan: Equatable, Sendable, Identifiable {
    /// Original path of the node.
    public var source: URL
    public var mediaType: MediaType
    public var status: PlanStatus
    /// Human-readable reason, mainly for skipped nodes.
    public var note: String
    /// The filesystem operations this node will perform when applied.
    public var operations: [Operation]
    /// Detected junk inside the node (offered for deletion later).
    public var junk: [URL]
    /// Before→after pairs for display (relative to the input root).
    public var previewPairs: [PreviewPair]
    /// If set, the final title contains preserved stopwords worth verifying.
    public var verifyTitle: String
    public var verifyWords: [String]

    // Editable fields (rename nodes only) — drive `PlanBuilder.replan`.
    /// Show name (TV) or movie title without the year (movie).
    public var editTitle: String
    /// Release year (movie); "" for TV.
    public var editYear: String
    /// Per-output-file data used to recompute destinations on edit.
    public var units: [RenameUnit]

    public var id: URL { source }

    public init(
        source: URL,
        mediaType: MediaType,
        status: PlanStatus,
        note: String = "",
        operations: [Operation] = [],
        junk: [URL] = [],
        previewPairs: [PreviewPair] = [],
        verifyTitle: String = "",
        verifyWords: [String] = [],
        editTitle: String = "",
        editYear: String = "",
        units: [RenameUnit] = []
    ) {
        self.source = source
        self.mediaType = mediaType
        self.status = status
        self.note = note
        self.operations = operations
        self.junk = junk
        self.previewPairs = previewPairs
        self.verifyTitle = verifyTitle
        self.verifyWords = verifyWords
        self.editTitle = editTitle
        self.editYear = editYear
        self.units = units
    }
}

/// A full plan for an input folder: every node plus the set of source URLs
/// caught in a duplicate-target conflict.
public struct Plan: Sendable {
    public let root: URL
    public let nodes: [NodePlan]
    public let conflicts: Set<URL>
    public init(root: URL, nodes: [NodePlan], conflicts: Set<URL>) {
        self.root = root
        self.nodes = nodes
        self.conflicts = conflicts
    }
}

public extension Plan {
    /// Sources that would move to the same destination, grouped by that shared
    /// target (only groups of two or more). Each group is sorted by path so the
    /// order is stable for display and tests.
    var conflictGroups: [[URL]] {
        var byDestination: [String: [URL]] = [:]
        for node in nodes {
            for case let .move(from, to) in node.operations {
                byDestination[to.standardizedFileURL.path, default: []].append(from)
            }
        }
        return byDestination.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.path < $1.path } }
            .sorted { ($0.first?.path ?? "") < ($1.first?.path ?? "") }
    }

    /// The conflict group that `source` belongs to, or nil if it is unconflicted.
    func conflictGroup(containing source: URL) -> [URL]? {
        conflictGroups.first { $0.contains(source) }
    }
}

public extension NodePlan {
    /// This node's move sources that are currently caught in a conflict.
    func conflictedSources(in conflicts: Set<URL>) -> [URL] {
        operations.compactMap {
            if case let .move(from, _) = $0, conflicts.contains(from) { return from }
            return nil
        }
    }
}
