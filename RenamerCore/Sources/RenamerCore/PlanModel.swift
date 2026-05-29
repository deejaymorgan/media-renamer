import Foundation

/// A single filesystem operation in a plan.
public enum Operation: Equatable, Sendable {
    /// Move (rename or relocate) a file from one URL to another.
    case move(from: URL, to: URL)
    /// Remove the source directory if it is empty after its contents moved out.
    case removeEmptyDirectory(URL)
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
        verifyWords: [String] = []
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
