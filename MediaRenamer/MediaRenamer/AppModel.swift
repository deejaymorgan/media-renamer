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

    // MARK: Output mode (three-level cascade: item → group → global)

    /// The global layout. **Rename-only at every launch, deliberately never
    /// persisted** — a flattening default that silently survived a relaunch would
    /// be exactly the surprise the mode guard exists to prevent. (The engine's own
    /// default is `.organise`, which keeps every non-UI call site unchanged.)
    private(set) var globalMode: OutputMode = .renameOnly
    /// "All TV" / "all Movies" overrides — three-state, so an untouched group
    /// defers to the global rather than pinning a mode.
    private(set) var tvOverride: ModeOverride = .inherit
    private(set) var movieOverride: ModeOverride = .inherit
    /// Per-node overrides, keyed by source URL — the same key the title-edit and
    /// disambiguation layers use, so it replays through `assemble` the same way.
    private(set) var itemOverrides: [URL: ModeOverride] = [:]

    private var cascade: ModeCascade {
        ModeCascade(global: globalMode, tv: tvOverride, movies: movieOverride,
                    items: itemOverrides)
    }

    /// TV show nodes (keyed by source URL) whose season children are expanded in
    /// the sidebar. Reset to empty (all shows collapsed) when a folder is chosen.
    private(set) var expandedShows: Set<URL> = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.acronymDefaultsKey),
           let raw = try? JSONDecoder().decode([String: String].self, from: data) {
            acronymModes = raw.compactMapValues(AcronymMode.init(rawValue:))
        }
    }

    /// Pick a NEW folder. Clears the group and item mode overrides too — they were
    /// decisions about the previous folder's contents. The *global* mode is a
    /// per-launch setting and is deliberately not reset here.
    func choose(_ url: URL) {
        tvOverride = .inherit
        movieOverride = .inherit
        itemOverrides = [:]
        rescan(url)
    }

    /// Re-read the folder already loaded. The other edit layers reset as before;
    /// mode overrides deliberately survive, because applying in several passes over
    /// one folder (resolve a duplicate, apply, resolve the next) is the workflow
    /// they were chosen for. This makes mode the only edit layer that outlives an
    /// Apply — that asymmetry is intended, not an oversight.
    private func rescan(_ url: URL) {
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

    // MARK: Output mode

    func setGlobalMode(_ mode: OutputMode) {
        guard mode != globalMode else { return }
        globalMode = mode
        rebuildPlan()
    }

    func groupOverride(for type: MediaType) -> ModeOverride {
        type == .tv ? tvOverride : movieOverride
    }

    func setGroupOverride(_ override: ModeOverride, for type: MediaType) {
        guard override != groupOverride(for: type) else { return }
        if type == .tv { tvOverride = override } else { movieOverride = override }
        rebuildPlan()
    }

    /// The item's own setting — `.inherit` when it defers to its group/global.
    func itemOverride(for source: URL) -> ModeOverride {
        itemOverrides[source] ?? .inherit
    }

    /// Set (or clear) one node's override. `.inherit` removes the entry rather than
    /// storing a no-op, so the map only ever holds real decisions.
    func setItemOverride(_ override: ModeOverride, for source: URL) {
        guard override != itemOverride(for: source) else { return }
        if override == .inherit { itemOverrides.removeValue(forKey: source) }
        else { itemOverrides[source] = override }
        rebuildPlan()
    }

    /// How many levels of the cascade are currently overriding the global
    /// layout: the two group settings plus every pinned item. Zero means the
    /// toolbar picker alone decides the whole plan.
    var overrideCount: Int {
        (tvOverride == .inherit ? 0 : 1)
            + (movieOverride == .inherit ? 0 : 1)
            + itemOverrides.count
    }

    /// Clear every group and item override at once, leaving the global picker in
    /// sole charge. One rebuild, not one per override.
    ///
    /// This is the plan-wide counterpart to a chip's "Inherit". It exists
    /// because overrides are easy to lose track of: they survive an Apply, and a
    /// group whose items have all been renamed keeps its section on screen
    /// purely so the header control stays reachable. Clearing them one row at a
    /// time means first finding the rows.
    func resetAllOverrides() {
        guard overrideCount > 0 else { return }
        tvOverride = .inherit
        movieOverride = .inherit
        itemOverrides = [:]
        rebuildPlan()
    }

    /// The mode a node would resolve to with no override of its own — what
    /// "Inherit" means for that node, so the UI can name it instead of leaving the
    /// default unexplained.
    func inheritedMode(for node: NodePlan) -> OutputMode {
        ModeCascade(global: globalMode, tv: tvOverride, movies: movieOverride)
            .mode(for: node.source, mediaType: node.mediaType)
    }

    /// Whether the sidebar offers this node as a selectable row: everything being
    /// renamed, plus an `.unchanged` node still pinned by an explicit override.
    ///
    /// That second case is not a nicety. Forcing organise mode onto an
    /// already-organised item leaves it with nothing to do, which drops it out of
    /// its section — taking the only control that could undo the choice with it.
    /// Keeping the row reachable means an explicit setting is always reversible in
    /// place, rather than only by re-picking the folder (which discards title
    /// edits, junk keeps and duplicate resolutions).
    func hasSelectableRow(_ node: NodePlan) -> Bool {
        node.status == .rename
            || (node.status == .unchanged && itemOverride(for: node.source) != .inherit)
    }

    private func rebuildPlan() {
        guard let folderURL else { return }
        // Build → stamp output modes → resolve duplicates → re-apply manual
        // title/year edits, so an edit survives an acronym-driven rebuild. The
        // four-pass ordering lives in PlanBuilder.assemble (a pure,
        // Foundation-only helper covered by RenamerCore tests); recording an edit
        // only on a real change — so merely viewing a node can't pin a phantom
        // edit and veto acronym toggles — is the UI-side guard in `replan` below.
        let p = PlanBuilder.assemble(root: folderURL, acronyms: acronymMap,
                                     cascade: cascade,
                                     disambiguation: disambiguation, titleEdits: titleEdits)
        plan = p
        // A mode toggle can flip a node between .rename and .unchanged (a file
        // already correctly named at the root has nothing to do in flat mode, but
        // plenty to do in organise mode). Only rename nodes have a selectable
        // sidebar row, so a selection left pointing at one that just changed status
        // would leave the list with nothing highlighted while the inspector still
        // showed it. Re-point instead of stranding.
        if let current = selection, !isSelectable(current, in: p) { selection = nil }
        if selection == nil {
            selection = p.nodes.first(where: { $0.status == .rename }).map { .item($0.source) } ?? .all
        }
    }

    /// Whether the sidebar has a row the selection can highlight.
    private func isSelectable(_ selection: Selection, in plan: Plan) -> Bool {
        switch selection {
        case .all:
            return true
        case .item(let url):
            return plan.nodes.first { $0.source == url }.map(hasSelectableRow) ?? false
        case .season(let show, let number):
            guard let node = plan.nodes.first(where: { $0.source == show }),
                  node.status == .rename, node.isMultiSeason else { return false }
            return node.seasonNumbers.contains(number)
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
    /// (Synchronous — fine for typical folders; move off-main if it ever blocks.)
    func apply() {
        guard let plan, let folderURL else { return }
        let result = Executor.apply(plan, trashing: junkToTrash, using: SystemTrasher())
        lastResult = result
        // Retire spent overrides BEFORE the re-scan, not after. An override is
        // keyed by source URL, so once its node's files have moved the key names a
        // path that no longer holds them — and a later item can end up at that same
        // path, silently inheriting a layout nobody chose for it. Pruning first, on
        // what actually moved, closes that; pruning afterwards would already have
        // rebuilt the plan through the stale key.
        //
        // What survives is exactly what §5.2 keeps them for: nodes that did NOT
        // move (skipped conflicts, unresolved duplicates), waiting for the next
        // pass over the same folder.
        let movedSources = Set(result.completedMoves.map(\.from))
        let stationary = Set(plan.nodes
            .filter { node in !node.units.contains { movedSources.contains($0.source) } }
            .map(\.source))
        itemOverrides = itemOverrides.filter { stationary.contains($0.key) }

        selection = nil
        // Re-scan the now-renamed tree through `rescan`, NOT `choose` — an Apply is
        // not a new folder, so the mode overrides survive it (see `rescan`).
        rescan(folderURL)
        pruneItemOverrides()
    }

    /// Drop per-item overrides whose node no longer exists at all, so the map can't
    /// grow without bound across repeated passes. Safe to run after the rebuild:
    /// it only ever removes keys the fresh plan has no node for, which by
    /// definition had no effect on that plan.
    private func pruneItemOverrides() {
        let live = Set(plan?.nodes.map(\.source) ?? [])
        itemOverrides = itemOverrides.filter { live.contains($0.key) }
    }

    // MARK: The apply guard

    /// The chosen folder's own name — what a flattened file's destination is
    /// called, in the preview band and in the confirmation dialog.
    var rootName: String { folderURL?.lastPathComponent ?? "" }

    /// Files that will move, split by the layout they land in. Both numbers are
    /// stated before Apply, so the active mode is never left to be inferred from
    /// silence and a mixed plan names both shapes with equal weight.
    var fileCountsByMode: (organise: Int, flat: Int) {
        let renaming = plan?.nodes.filter { $0.status == .rename } ?? []
        func files(_ mode: OutputMode) -> Int {
            renaming.filter { $0.outputMode == mode }.reduce(0) { $0 + $1.previewPairs.count }
        }
        return (files(.organise), files(.renameOnly))
    }

    /// Whether the organised half of the plan contains TV, movies, or both — so
    /// the dialog can name the tree it will actually build instead of reciting
    /// both shapes and describing folders that will never exist.
    var organisedKinds: (tv: Bool, movie: Bool) {
        let organised = plan?.nodes.filter { $0.status == .rename && $0.outputMode == .organise } ?? []
        return (organised.contains { $0.mediaType == .tv },
                organised.contains { $0.mediaType == .movie })
    }

    /// Source folders that will be removed once emptied. The executor only removes
    /// a folder that is genuinely empty at apply time, so this is an upper bound —
    /// but it is the hardest part of a run to walk back, and it is invisible in the
    /// preview, so it is named explicitly before Apply.
    var folderRemovalCount: Int {
        (plan?.nodes ?? [])
            .filter { $0.status == .rename }
            .reduce(0) { total, node in
                total + node.operations.filter {
                    if case .removeEmptyDirectory = $0 { return true } else { return false }
                }.count
            }
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

/// The plan's nodes split into the display buckets the sidebar shows.
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

    /// The label shown for the whole node: a TV show's name (seasons live below
    /// it) or a movie's `Title (Year)`. Derived from the editable fields rather
    /// than from the destination path, so it reads identically in both output
    /// modes — a flattened movie has no destination folder to name.
    ///
    /// The fields are put through the engine's own sanitisation first, because
    /// this label is presented as the *result* (`AllCard` renders it after an
    /// arrow). A title of `Mission: Impossible` lands on disk as
    /// `Mission- Impossible`, and a cleared one as `Untitled`; showing anything
    /// else here would advertise a name the plan will not produce.
    var displayTitle: String {
        guard !units.isEmpty else { return originalName }   // skipped nodes have no plan
        let safe = PlanBuilder.sanitizeSeparators(editTitle)
        let title = (safe.isEmpty || safe.allSatisfy { $0 == "." }) ? "Untitled" : safe
        guard mediaType != .tv else { return title }
        let year = PlanBuilder.sanitizeSeparators(editYear)
        return year.isEmpty ? title : "\(title) (\(year))"
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
        // Unit-aware, not move-only: a resident occupant already in place emits no
        // move op but is still flagged, so its node must show the badge too.
        units.contains { conflicts.contains($0.source) }
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
            // The destination filename the group is fighting over: a mover's
            // `to`, or — for a resident in-place unit with no move op — its own
            // current name (which already IS its destination). Never "", so the
            // resolver always shows a real target.
            let target = operations.compactMap { op -> String? in
                if case let .move(from, to) = op, from == src { return to.lastPathComponent }
                return nil
            }.first ?? src.lastPathComponent
            out.append((group, target))
        }
        return out
    }

    // MARK: - Title verify flag

    /// True when the editable title carries a "joined" hyphen (letter-hyphen-
    /// letter, e.g. `Spider-Man` or `The-Bear`). The engine preserves such
    /// hyphens verbatim, but a scene release sometimes uses `-` as a word
    /// separator (`the-bear` → `The-Bear`), so it's worth a human glance. The
    /// spaced `" - "` the engine produces from a source colon is deliberately
    /// excluded — it isn't suspect.
    var titleHasJoinedHyphen: Bool {
        editTitle.range(of: #"\S-\S"#, options: .regularExpression) != nil
    }

    /// The concrete, user-facing reasons the title is flagged — each a complete,
    /// actionable sentence. Empty when nothing needs a look. Drives both the
    /// badge tooltip and the inline note, so the flag is never unexplained.
    var verifyReasons: [String] {
        var reasons: [String] = []
        if titleHasJoinedHyphen {
            reasons.append("Kept a hyphen as-is — change it to a space if it was a word separator (e.g. “the-bear”).")
        }
        if !verifyWords.isEmpty {
            let list = verifyWords.map { "“\($0)”" }.joined(separator: ", ")
            reasons.append("Kept \(list) capitalized as in the source — title case usually lowercases such mid-title words, so confirm it reads right.")
        }
        return reasons
    }

    /// Whether to raise the orange verify flag.
    var needsVerify: Bool { !verifyReasons.isEmpty }

    /// Tooltip text for the badge (the reasons, one per line).
    var verifyHint: String { verifyReasons.joined(separator: "\n") }
}
