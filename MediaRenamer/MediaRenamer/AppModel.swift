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
    /// User overrides per word; persisted across launches.
    private(set) var acronymModes: [String: AcronymMode] = [:]

    /// Junk the user chose to KEEP (unchecked). Everything else is trashed.
    private(set) var keptJunk: Set<URL> = []
    /// Per-source version labels chosen in the resolve panel, keyed by the unit's
    /// source URL. Re-applied after every rebuild so resolutions survive edits.
    private(set) var disambiguation: [URL: String] = [:]
    /// Outcome of the most recent Apply.
    private(set) var lastResult: ApplyResult?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.acronymDefaultsKey),
           let raw = try? JSONDecoder().decode([String: String].self, from: data) {
            acronymModes = raw.compactMapValues(AcronymMode.init(rawValue:))
        }
    }

    func choose(_ url: URL) {
        folderURL = url
        keptJunk = []
        disambiguation = [:]
        acronymWords = PlanBuilder.allCapsWords(root: url)
        selection = nil
        rebuildPlan()
    }

    // MARK: Acronyms

    func mode(for word: String) -> AcronymMode {
        acronymModes[word] ?? (word.count <= 4 ? .keep : .title)
    }

    func setMode(_ mode: AcronymMode, for word: String) {
        acronymModes[word] = mode
        persistAcronymModes()
        rebuildPlan()
    }

    private var acronymMap: [String: String] {
        var map: [String: String] = [:]
        for word in acronymWords where mode(for: word) == .keep { map[word] = word }
        return map
    }

    private func rebuildPlan() {
        guard let folderURL else { return }
        var p = PlanBuilder.plan(root: folderURL, acronyms: acronymMap)
        if !disambiguation.isEmpty { p = PlanBuilder.resolve(p, suffixes: disambiguation) }
        plan = p
        if selection == nil {
            selection = p.nodes.first(where: { $0.status == .rename }).map { .item($0.source) } ?? .all
        }
    }

    // MARK: Editing

    /// Apply a title/year edit to one item and re-detect conflicts.
    func replan(itemSource: URL, title: String, year: String) {
        guard let plan,
              let node = plan.nodes.first(where: { $0.source == itemSource }),
              node.editTitle != title || node.editYear != year
        else { return }
        self.plan = PlanBuilder.replan(plan, itemSource: itemSource, title: title, year: year)
    }

    // MARK: Duplicate resolution

    /// Assign version labels (keyed by source URL) to a conflict group and
    /// re-detect conflicts. Distinct labels clear the collision.
    func resolve(_ labels: [URL: String]) {
        for (src, label) in labels { disambiguation[src] = label }
        applyDisambiguation()
    }

    /// Leave a conflict unresolved: clear any labels so the sources keep their
    /// shared target (and stay skipped at apply).
    func skipConflict(_ sources: [URL]) {
        for src in sources { disambiguation[src] = "" }
        applyDisambiguation()
    }

    private func applyDisambiguation() {
        guard let plan else { return }
        self.plan = PlanBuilder.resolve(plan, suffixes: disambiguation)
    }

    // MARK: Junk

    func isJunkTrashed(_ url: URL) -> Bool { !keptJunk.contains(url) }

    func setJunkTrashed(_ url: URL, _ trash: Bool) {
        if trash { keptJunk.remove(url) } else { keptJunk.insert(url) }
    }

    /// Junk approved for the Trash (everything not explicitly kept).
    var junkToTrash: [URL] {
        (plan?.nodes.flatMap { $0.junk } ?? []).filter { !keptJunk.contains($0) }
    }

    // MARK: Apply

    /// Trash approved junk, perform the renames, then re-scan the folder.
    /// (Synchronous for now — fine for typical folders; move off-main if needed.)
    func apply() {
        guard let plan, let folderURL else { return }
        lastResult = Executor.apply(plan, trashing: junkToTrash, using: SystemTrasher())
        selection = nil
        choose(folderURL)   // re-scan the now-renamed tree
    }

    var lastResultSummary: String? {
        guard let r = lastResult else { return nil }
        var parts = ["Moved \(r.movedCount)"]
        if r.trashedCount > 0 { parts.append("Trashed \(r.trashedCount)") }
        if r.conflictCount > 0 { parts.append("Skipped \(r.conflictCount)") }
        if r.errorCount > 0 { parts.append("Errors \(r.errorCount)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Persistence

    private static let acronymDefaultsKey = "acronymModes"

    private func persistAcronymModes() {
        let raw = acronymModes.mapValues(\.rawValue)
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.acronymDefaultsKey)
        }
    }
}

/// The plan's nodes split into display buckets (same grouping the CLI uses).
struct PlanGroups {
    let tvRename: [NodePlan]
    let movieRename: [NodePlan]
    let unchanged: [NodePlan]
    let skipped: [NodePlan]
    let junkCount: Int

    init(_ plan: Plan) {
        tvRename = plan.nodes.filter { $0.mediaType == .tv && $0.status == .rename }
        movieRename = plan.nodes.filter { $0.mediaType == .movie && $0.status == .rename }
        unchanged = plan.nodes.filter { $0.status == .unchanged }
        skipped = plan.nodes.filter { $0.status == .skip }
        junkCount = plan.nodes.reduce(0) { $0 + $1.junk.count }
    }
}

extension NodePlan {
    var originalName: String { source.lastPathComponent }

    var destinationDirectory: String {
        guard let first = previewPairs.first else { return originalName }
        let parts = first.new.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : first.new
    }

    func isConflicted(in conflicts: Set<URL>) -> Bool {
        operations.contains { op in
            if case let .move(from, _) = op { return conflicts.contains(from) }
            return false
        }
    }

    /// The distinct conflict groups this node takes part in, each paired with
    /// the shared destination filename the group is fighting over. Usually one.
    func displayConflicts(in plan: Plan) -> [(group: [URL], target: String)] {
        var seen = Set<String>()
        var out: [(group: [URL], target: String)] = []
        for src in conflictedSources(in: plan.conflicts) {
            guard let group = plan.conflictGroup(containing: src) else { continue }
            let key = group.map(\.path).joined(separator: "|")
            guard seen.insert(key).inserted else { continue }
            let target = operations.compactMap { op -> String? in
                if case let .move(from, to) = op, from == src { return to.lastPathComponent }
                return nil
            }.first ?? ""
            out.append((group, target))
        }
        return out
    }
}
