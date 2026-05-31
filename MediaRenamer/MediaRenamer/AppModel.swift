import Foundation
import Observation
import RenamerCore

/// What the sidebar has selected: "All items" mode, or one specific item.
enum Selection: Hashable {
    case all
    case item(URL)
}

@MainActor
@Observable
final class AppModel {
    private(set) var folderURL: URL?
    private(set) var plan: Plan?
    var selection: Selection?

    func choose(_ url: URL) {
        folderURL = url
        let p = PlanBuilder.plan(root: url)
        plan = p
        // Default to the first editable item; fall back to All mode.
        if let first = p.nodes.first(where: { $0.status == .rename }) {
            selection = .item(first.source)
        } else {
            selection = .all
        }
    }

    /// Apply a title/year edit to one item and re-detect conflicts. No-ops if
    /// nothing actually changed (keeps live editing cheap and flicker-free).
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
