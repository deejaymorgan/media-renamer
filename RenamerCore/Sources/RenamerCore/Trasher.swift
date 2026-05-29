import Foundation

/// The result of attempting to trash a single item.
public struct TrashOutcome: Sendable {
    public let source: URL
    /// Where it landed in the Trash (for cleanup/reporting), if successful.
    public let trashedTo: URL?
    public let error: String?
}

/// Moves files/folders to the Trash. Abstracted so callers and tests don't
/// have to depend on the real system Trash.
public protocol Trasher: Sendable {
    func trash(_ urls: [URL]) -> [TrashOutcome]
}

/// Real macOS Trash via `FileManager.trashItem` — items keep the system's
/// "Put Back" affordance for free.
public struct SystemTrasher: Trasher {
    public init() {}

    public func trash(_ urls: [URL]) -> [TrashOutcome] {
        urls.map { url in
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                return TrashOutcome(source: url, trashedTo: resulting.map { $0 as URL }, error: nil)
            } catch {
                return TrashOutcome(source: url, trashedTo: nil, error: error.localizedDescription)
            }
        }
    }
}
