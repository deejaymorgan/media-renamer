import Foundation
import Observation
import RenamerCore

/// What the sidebar has selected: "All items" mode, or one specific item.
enum Selection: Hashable {
    case all
    case item(URL)
}

/// How an all-caps word is rendered everywhere it appears.
enum AcronymMode: String {
    case keep   // "WALL" stays "WALL"
    case title  // "WALL" → "Wall"
}

@MainActor
@Observable
final class AppModel {
    private(set) var folderURL: URL?
    private(set) var plan: Plan?
    var selection: Selection?

    /// All-caps words found in the current folder (acronym candidates).
    private(set) var acronymWords: [String] = []
    /// User overrides per word; words without an override use the default rule.
    private(set) var acronymModes: [String: AcronymMode] = [:]

    func choose(_ url: URL) {
        folderURL = url
        acronymWords = PlanBuilder.allCapsWords(root: url)
        selection = nil
        rebuildPlan()
    }

    /// The decision for a word: a user override, else the default (keep ≤4 chars).
    func mode(for word: String) -> AcronymMode {
        acronymModes[word] ?? (word.count <= 4 ? .keep : .title)
    }

    /// Change a word's decision and re-plan the whole folder live.
    func setMode(_ mode: AcronymMode, for word: String) {
        acronymModes[word] = mode
        rebuildPlan()
    }

    /// Engine acronym map — only "keep" words need an entry (title mode is the
    /// engine's default for unknown all-caps words).
    private var acronymMap: [String: String] {
        var map: [String: String] = [:]
        for word in acronymWords where mode(for: word) == .keep { map[word] = word }
        return map
    }

    private func rebuildPlan() {
        guard let folderURL else { return }
        let p = PlanBuilder.plan(root: folderURL, acronyms: acronymMap)
        plan = p
        if selection == nil {
            selection = p.nodes.first(where: { $0.status == .rename }).map { .item($0.source) } ?? .all
        }
    }

    /// Apply a title/year edit to one item and re-detect conflicts. No-ops if
    /// nothing changed (keeps live editing cheap and flicker-free).
    func replan(itemSource: URL, title: String, year: String) {
        guard let plan,
              let node = plan.nodes.first(where: { $0.source == itemSource }),
              node.editTitle != title || node.editYear != year
        else { return }
        self.plan = PlanBuilder.replan(plan, itemSource: itemSource, title: title, year: year)
    }
}

/// The plan's nodes split into display buckets (same grouping the CLI uses).
struct PlanGroups {
    let tvRename: [NodePlan]
    let movieRename: [NodePlan]
    let unchanged: [NodePlan]
    let skipped: [NodePlan]
    let verify: [NodePlan]
    let junkCount: Int

    init(_ plan: Plan) {
        tvRename = plan.nodes.filter { $0.mediaType == .tv && $0.status == .rename }
        movieRename = plan.nodes.filter { $0.mediaType == .movie && $0.status == .rename }
        unchanged = plan.nodes.filter { $0.status == .unchanged }
        skipped = plan.nodes.filter { $0.status == .skip }
        verify = plan.nodes.filter { !$0.verifyTitle.isEmpty }
        junkCount = plan.nodes.reduce(0) { $0 + $1.junk.count }
    }
}

extension NodePlan {
    /// The original folder/file name, for display.
    var originalName: String { source.lastPathComponent }

    /// The destination directory (filename dropped) — the item's friendly name
    /// in the list/inspector, e.g. "Breaking Bad/Season 1".
    var destinationDirectory: String {
        guard let first = previewPairs.first else { return originalName }
        let parts = first.new.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : first.new
    }

    /// Whether any of this node's moves collide with another's destination.
    func isConflicted(in conflicts: Set<URL>) -> Bool {
        operations.contains { op in
            if case let .move(from, _) = op { return conflicts.contains(from) }
            return false
        }
    }
}
