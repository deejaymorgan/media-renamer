import Foundation

/// A move that was actually performed — kept so a future "undo last run" can
/// reverse it.
public struct CompletedMove: Sendable, Equatable {
    public let from: URL
    public let to: URL
}

/// The outcome of applying a plan.
public struct ApplyResult: Sendable {
    /// Files successfully moved.
    public internal(set) var movedCount = 0
    /// Moves skipped due to a batch conflict or an already-existing destination.
    public internal(set) var conflictCount = 0
    /// Operations that failed with an error.
    public internal(set) var errorCount = 0
    /// Junk files successfully moved to the Trash.
    public internal(set) var trashedCount = 0
    /// Completed moves, in order (for an undo step later).
    public internal(set) var completedMoves: [CompletedMove] = []
    /// Human-readable log lines for skips and errors.
    public internal(set) var messages: [String] = []
    public init() {}
}

/// Performs a plan's filesystem operations. Ported from `execute_plans`.
///
/// Only `.rename` nodes act. A node is skipped entirely if any of its move
/// sources is in the conflict set; an individual move is skipped if its
/// destination already exists on disk. A restructured folder's source is
/// removed only if it ends up empty. `unchanged`/`skip` nodes are untouched.
/// Junk deletion is separate (see `Trasher`).
///
/// Synchronous; the app should call it off the main actor.
public enum Executor {

    public static func apply(_ plan: Plan) -> ApplyResult {
        apply(nodes: plan.nodes, conflicts: plan.conflicts)
    }

    /// Trash the approved junk first (so emptied source folders can be cleaned
    /// up), then perform the renames. Returns one combined result.
    public static func apply(_ plan: Plan, trashing junk: [URL], using trasher: Trasher) -> ApplyResult {
        let outcomes = trasher.trash(junk)
        var result = apply(plan)
        result.trashedCount = outcomes.filter { $0.error == nil }.count
        for outcome in outcomes where outcome.error != nil {
            result.errorCount += 1
            result.messages.append("Trash failed: \(outcome.source.lastPathComponent)")
        }
        return result
    }

    public static func apply(nodes: [NodePlan], conflicts: Set<URL>) -> ApplyResult {
        var result = ApplyResult()
        let fm = FileManager.default

        for node in nodes where node.status == .rename {
            // Batch conflict: if any move source collides, skip the whole node.
            let conflicted = node.operations.filter { op in
                if case let .move(from, _) = op { return conflicts.contains(from) }
                return false
            }
            if !conflicted.isEmpty {
                result.conflictCount += conflicted.count
                continue
            }

            for op in node.operations {
                switch op {
                case let .move(from, to):
                    if fm.fileExists(atPath: to.path) {
                        result.conflictCount += 1
                        result.messages.append("Skipped (target exists): \(to.lastPathComponent)")
                        continue
                    }
                    do {
                        try fm.createDirectory(at: to.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
                        try fm.moveItem(at: from, to: to)
                        result.completedMoves.append(CompletedMove(from: from, to: to))
                        result.movedCount += 1
                    } catch {
                        result.errorCount += 1
                        result.messages.append(
                            "Error moving \(from.lastPathComponent): \(error.localizedDescription)")
                    }
                case let .removeEmptyDirectory(dir):
                    let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                    // A non-empty source is expected (kept junk / skipped files)
                    // and left in place silently; only a genuine removal failure
                    // on an emptied folder is worth reporting.
                    guard contents.isEmpty else { continue }
                    do {
                        try fm.removeItem(at: dir)
                    } catch {
                        result.errorCount += 1
                        result.messages.append(
                            "Couldn't remove emptied folder \(dir.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }
        return result
    }
}
