import Foundation

/// Detects when two different sources would land on the same destination.
/// Ported from `detect_dest_conflicts`, then extended to catch two cases the
/// move-op-only check missed (both verified to silently orphan a file on Apply):
///   • a move onto a slot a file already occupies in place (the upgrade / re-run
///     workflow — the resident file produces no move op, so the incoming move was
///     the only op for that destination and went unflagged); and
///   • case-only collisions on a case-insensitive volume (the macOS default),
///     where two destinations differing only in letter case are the same path on
///     disk but were two distinct dictionary keys.
public enum ConflictChecker {

    /// The set of source URLs whose destination collides with another's.
    public static func detect(in plans: [NodePlan]) -> Set<URL> {
        let index = destinationIndex(in: plans,
                                     caseInsensitive: caseInsensitiveVolume(plans.first?.source))
        var conflicts: Set<URL> = []
        for (_, sources) in index where Set(sources).count > 1 {
            conflicts.formUnion(sources)
        }
        return conflicts
    }

    /// Map each destination (case-folded on a case-insensitive volume) to the
    /// sources landing there: every move target, plus every in-place unit (one
    /// already at its destination, which a colliding move would silently skip).
    /// Shared with `Plan.conflictGroups` so detection and display always agree.
    static func destinationIndex(in plans: [NodePlan], caseInsensitive: Bool) -> [String: [URL]] {
        var index: [String: [URL]] = [:]
        for node in plans {
            var moved: Set<URL> = []
            for case let .move(from, to) in node.operations {
                moved.insert(from)
                index[key(to, caseInsensitive: caseInsensitive), default: []].append(from)
            }
            // A unit with no move op is already at its destination; record it as
            // the resident occupant so an incoming move to the same slot collides.
            for unit in node.units where !moved.contains(unit.source) {
                index[key(unit.source, caseInsensitive: caseInsensitive), default: []].append(unit.source)
            }
        }
        return index
    }

    /// The dictionary key for a destination path — case-folded when the target
    /// volume is case-insensitive, so two destinations differing only by case
    /// collide here exactly as they would on disk.
    static func key(_ url: URL, caseInsensitive: Bool) -> String {
        let path = url.standardizedFileURL.path
        return caseInsensitive ? path.lowercased() : path
    }

    /// Whether `url`'s volume treats names case-insensitively (the macOS default).
    /// Assumes case-insensitive when the URL is nil or the volume can't be probed.
    static func caseInsensitiveVolume(_ url: URL?) -> Bool {
        guard let url else { return true }
        if let sensitive = (try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames {
            return !sensitive
        }
        return true
    }
}
