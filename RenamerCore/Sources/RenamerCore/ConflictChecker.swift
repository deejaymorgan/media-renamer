import Foundation

/// Detects when two different sources would move to the same destination.
/// Ported from `detect_dest_conflicts`.
public enum ConflictChecker {

    /// The set of source URLs whose move destination collides with another's.
    public static func detect(in plans: [NodePlan]) -> Set<URL> {
        var destinationToSources: [String: [URL]] = [:]
        for plan in plans {
            for op in plan.operations {
                if case let .move(from, to) = op {
                    destinationToSources[to.standardizedFileURL.path, default: []].append(from)
                }
            }
        }
        var conflicts: Set<URL> = []
        for (_, sources) in destinationToSources where sources.count > 1 {
            conflicts.formUnion(sources)
        }
        return conflicts
    }
}
