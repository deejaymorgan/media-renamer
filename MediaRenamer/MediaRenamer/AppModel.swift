import Foundation
import Observation
import RenamerCore

/// What the sidebar has selected: "All items" mode, a whole show/movie, or one
/// season of a show (identified by the show's source URL + season number).
enum Selection: Hashable {
    case all
    case item(URL)
    case season(show: URL, number: Int)
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
    /// Per-node title/year edits, keyed by the node's source URL. Re-applied after
    /// every rebuild so a manual edit survives an acronym toggle (which rebuilds
    /// the whole plan), exactly the way `disambiguation` survives it.
    private(set) var titleEdits: [URL: (title: String, year: String)] = [:]
    /// Outcome of the most recent Apply.
    private(set) var lastResult: ApplyResult?

    /// TV show nodes (keyed by source URL) whose season children are expanded in
    /// the sidebar. Reset to empty (all shows collapsed) when a folder is chosen.
    private(set) var expandedShows: Set<URL> = []

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
        titleEdits = [:]
        acronymWords = PlanBuilder.allCapsWords(root: url)
        selection = nil
        rebuildPlan()
        collapseAllShows()
    }

    // MARK: Sidebar season tree

    /// Source URLs of TV shows that span more than one season (the expandable rows).
    private var multiSeasonShowSources: [URL] {
        (plan?.nodes ?? [])
            .filter { $0.mediaType == .tv && $0.status == .rename && $0.isMultiSeason }
            .map(\.source)
    }

    /// Whether any show has multiple seasons (drives the Expand/Collapse bar).
    var hasMultiSeasonShow: Bool { !multiSeasonShowSources.isEmpty }

    func isShowExpanded(_ source: URL) -> Bool { expandedShows.contains(source) }
    func expandAllShows() { expandedShows = Set(multiSeasonShowSources) }
    func collapseAllShows() { expandedShows = [] }
    func toggleShow(_ source: URL) {
        if expandedShows.contains(source) { expandedShows.remove(source) }
        else { expandedShows.insert(source) }
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
        // Build → resolve duplicates → re-apply manual title/year edits, so an
        // edit survives an acronym-driven rebuild. The three-pass ordering lives
        // in PlanBuilder.assemble (a pure, Foundation-only helper covered by
        // RenamerCore tests); recording an edit only on a real change — so merely
        // viewing a node can't pin a phantom edit and veto acronym toggles — is
        // the UI-side guard in `replan` below.
        let p = PlanBuilder.assemble(root: folderURL, acronyms: acronymMap,
                                     disambiguation: disambiguation, titleEdits: titleEdits)
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
        // Record only a REAL change (after the unchanged-guard) so it survives
        // later rebuilds (e.g. an acronym toggle). Recording before the guard
        // would let a mere inspector appearance — EditFields.onAppear assigns the
        // current title, firing onChange — pin the node and silently veto acronym
        // toggles for it.
        titleEdits[itemSource] = (title, year)
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
        var summary = parts.joined(separator: " · ")
        // Surface the actual reasons behind any skips/errors — the counts alone
        // don't tell the user *what* failed. Capped so the alert stays readable.
        if !r.messages.isEmpty {
            let shown = r.messages.prefix(6).joined(separator: "\n")
            let more = r.messages.count > 6 ? "\n…and \(r.messages.count - 6) more" : ""
            summary += "\n\n" + shown + more
        }
        return summary
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

/// One season's slice of a TV show node: the season number and the before→after
/// pairs (and their source URLs, for scoping conflicts) that land in it.
struct SeasonSlice: Identifiable {
    let number: Int
    let pairs: [PreviewPair]
    let sources: [URL]
    var id: Int { number }
}

extension NodePlan {
    var originalName: String { source.lastPathComponent }

    var destinationDirectory: String {
        guard let first = previewPairs.first else { return originalName }
        let parts = first.new.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : first.new
    }

    /// The label shown for the whole node: a TV show's name (seasons live below
    /// it), or a movie's destination folder.
    var displayTitle: String {
        guard mediaType == .tv else { return destinationDirectory }
        return editTitle.isEmpty ? originalName : editTitle
    }

    /// Distinct season numbers in this node, ascending. Empty for movies.
    var seasonNumbers: [Int] { Set(units.compactMap(\.season)).sorted() }

    var isMultiSeason: Bool { seasonNumbers.count > 1 }

    /// The node's files grouped by season, ascending. `units[i]` aligns with
    /// `previewPairs[i]` (both are built in unit order), so they zip cleanly.
    var seasonSlices: [SeasonSlice] {
        var byNumber: [Int: (pairs: [PreviewPair], sources: [URL])] = [:]
        for (i, unit) in units.enumerated() {
            guard let n = unit.season, i < previewPairs.count else { continue }
            byNumber[n, default: ([], [])].pairs.append(previewPairs[i])
            byNumber[n, default: ([], [])].sources.append(unit.source)
        }
        return byNumber.keys.sorted().map {
            SeasonSlice(number: $0, pairs: byNumber[$0]!.pairs, sources: byNumber[$0]!.sources)
        }
    }

    func seasonSlice(_ number: Int) -> SeasonSlice? { seasonSlices.first { $0.number == number } }

    /// A one-line season + file-count summary, e.g. "Season 1 · 2 files" or
    /// "Seasons 1–3 · 7 files" (a comma list when the seasons aren't contiguous).
    var seasonSummary: String {
        let ns = seasonNumbers
        let files = "\(previewPairs.count) file\(previewPairs.count == 1 ? "" : "s")"
        guard let lo = ns.first, let hi = ns.last else { return files }
        if ns.count == 1 { return "Season \(lo) · \(files)" }
        let span = (hi - lo == ns.count - 1) ? "\(lo)–\(hi)" : ns.map(String.init).joined(separator: ", ")
        return "Seasons \(span) · \(files)"
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
