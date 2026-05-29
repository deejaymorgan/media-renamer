import Foundation
import Observation
import RenamerCore

/// The app's single source of truth. `@Observable` means SwiftUI views that read
/// its properties re-render automatically when they change. `@MainActor` keeps
/// all access on the main thread (it's UI state).
@MainActor
@Observable
final class AppModel {
    /// The folder the user picked, if any.
    private(set) var folderURL: URL?
    /// The computed rename plan for that folder.
    private(set) var plan: Plan?

    /// Pick a folder and (re)build its plan.
    func choose(_ url: URL) {
        folderURL = url
        rebuild()
    }

    /// Recompute the plan for the current folder.
    ///
    /// Synchronous for now — the engine is fast for typical folders. If a huge
    /// library ever makes this feel laggy, we'll move it onto a background task
    /// (the engine is already `Sendable`-clean for that).
    func rebuild() {
        guard let folderURL else { return }
        plan = PlanBuilder.plan(root: folderURL)
    }
}
