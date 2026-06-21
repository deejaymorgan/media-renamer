import Foundation

/// Turns an input folder into node plans (and a full `Plan` with conflicts).
/// Ported from `plan_input_dir` / `plan_loose` / `plan_folder`, extended so that
/// loose files belonging to the same show (TV) or title+year (movie) are
/// grouped into one node the way a subfolder already is — and merge into a
/// matching subfolder's node when one exists.
public enum PlanBuilder {

    /// Build a full plan (nodes + conflicts) for `root`.
    public static func plan(root: URL, acronyms: [String: String] = [:]) -> Plan {
        let nodes = build(root: root, acronyms: acronyms)
        return Plan(root: root, nodes: nodes, conflicts: ConflictChecker.detect(in: nodes))
    }

    /// Assemble a full plan the way the app's rebuild does, in one place: build
    /// from `root` with the given acronym map, apply version-label
    /// disambiguation, then re-apply manual title/year edits (each keyed by a
    /// node's source URL). Sharing this ordering between the UI and tests is what
    /// lets a manual title edit survive an acronym-map change, which rebuilds the
    /// whole plan from scratch — `disambiguation`/`titleEdits` are re-applied on
    /// top exactly as they were the first time.
    ///
    /// Each edit targets its own node and every `replan` re-detects conflicts
    /// across the full plan, so the iteration order over `titleEdits` does not
    /// affect the result.
    public static func assemble(root: URL,
                                acronyms: [String: String] = [:],
                                disambiguation: [URL: String] = [:],
                                titleEdits: [URL: (title: String, year: String)] = [:]) -> Plan {
        var p = plan(root: root, acronyms: acronyms)
        if !disambiguation.isEmpty { p = resolve(p, suffixes: disambiguation) }
        for (src, edit) in titleEdits {
            p = replan(p, itemSource: src, title: edit.title, year: edit.year)
        }
        return p
    }

    /// Node plans for `root`. Subfolders and unrecognised loose files keep their
    /// own node; loose video files that share a show (TV) or title+year
    /// (movie) collapse into a single node — and, when the root also holds a
    /// subfolder for that same show/movie, fold into *its* node instead.
    public static func build(root: URL, acronyms: [String: String] = [:]) -> [NodePlan] {
        // Fixed nodes (subfolders + unrecognised loose files), keyed by their
        // position in the listing so the final order matches the input.
        var fixed: [Int: NodePlan] = [:]
        // Recognised loose videos, awaiting grouping.
        var loose: [(index: Int, url: URL, parse: MediaParse)] = []

        for (i, entry) in Scanner.listDir(root).enumerated() {
            let base = entry.lastPathComponent
            if Scanner.isSymlink(entry) {
                // Don't follow symlinks at the root (mirrors Scanner.walk's
                // no-follow rule for nested dirs): a link out of the tree would
                // pull in — and on Apply, relocate — files the user never chose,
                // and a self-referential one could loop. Skip, don't treat as junk.
                fixed[i] = NodePlan(source: entry, mediaType: .unknown, status: .skip,
                                    note: "symlink (not followed)")
            } else if !Scanner.isDirectory(entry) {
                let ext = Str.splitext(base).ext.lowercased()
                if !Constants.videoExtensions.contains(ext) {
                    fixed[i] = NodePlan(source: entry, mediaType: .unknown, status: .skip,
                                        note: "loose non-video file at root")
                } else if let parse = MediaParser.tv(base, acronyms: acronyms)
                            ?? MediaParser.movie(base, acronyms: acronyms) {
                    loose.append((i, entry, parse))
                } else {
                    fixed[i] = NodePlan(source: entry, mediaType: .unknown, status: .skip,
                                        note: "no episode code or release year")
                }
            } else if Constants.ignoredFolderNames.contains(base.lowercased()) {
                fixed[i] = NodePlan(source: entry, mediaType: .unknown, status: .skip,
                                    note: "ignored library folder: \(base)")
            } else {
                fixed[i] = planDirectory(entry, root: root, acronyms: acronyms)
            }
        }

        // Group loose videos by show / title+year, in first-seen order.
        var groups: [String: [(index: Int, url: URL, parse: MediaParse)]] = [:]
        var order: [String] = []
        for item in loose {
            let key = groupKey(item.parse)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }

        // Each group folds into a matching subfolder node, or becomes its own.
        var grouped: [(index: Int, node: NodePlan)] = []
        for key in order {
            let items = groups[key]!
            let parses = items.map { ($0.url, $0.parse) }
            if let target = mergeTarget(for: items[0].parse, in: fixed) {
                fixed[target] = merge(parses, into: fixed[target]!, root: root)
            } else if items.count == 1 {
                grouped.append((items[0].index,
                                planLoose(items[0].url, root: root, parse: items[0].parse)))
            } else {
                grouped.append((items[0].index, planLooseGroup(parses, root: root)))
            }
        }

        // Reassemble in input order (a loose group sits at its first member).
        return (fixed.map { (index: $0.key, node: $0.value) } + grouped)
            .sorted { $0.index < $1.index }
            .map(\.node)
    }

    /// Grouping key: all TV files of one show share a node (seasons are split at
    /// the destination and surfaced in the UI, not as separate nodes); movie
    /// files group per title — which already carries the year, e.g. `"Inception (2010)"`.
    private static func groupKey(_ p: MediaParse) -> String {
        p.episodeCode != nil ? "tv\u{0}\(p.title)" : "movie\u{0}\(p.title)"
    }

    /// The index of a subfolder node this loose parse should fold into: a
    /// non-skip TV folder for the same show, or movie folder for the same
    /// title+year. Among several, prefer one that already holds this season,
    /// else the earliest. nil when nothing matches.
    private static func mergeTarget(for p: MediaParse, in fixed: [Int: NodePlan]) -> Int? {
        let isTV = p.episodeCode != nil
        let matches = fixed.filter { _, node in
            guard node.status != .skip, node.mediaType == (isTV ? .tv : .movie) else { return false }
            return isTV ? node.editTitle == p.title
                        : "\(node.editTitle) (\(node.editYear))" == p.title
        }.keys.sorted()
        guard !matches.isEmpty else { return nil }
        if isTV, let season = p.season,
           let withSeason = matches.first(where: { fixed[$0]!.units.contains { $0.season == season } }) {
            return withSeason
        }
        return matches.first
    }

    /// Unique all-caps words across the folder's video filenames — the
    /// candidates for acronym keep/Title decisions.
    public static func allCapsWords(root: URL) -> [String] {
        var names: [String] = []
        for entry in Scanner.listDir(root) {
            if Scanner.isSymlink(entry) { continue }   // don't follow links at the root
            if Scanner.isDirectory(entry) {
                if Constants.ignoredFolderNames.contains(entry.lastPathComponent.lowercased()) { continue }
                names += Scanner.scanContents(entry).videos.map { $0.lastPathComponent }
            } else if Constants.videoExtensions.contains(Str.splitext(entry.lastPathComponent).ext.lowercased()) {
                names.append(entry.lastPathComponent)
            }
        }
        return MediaParser.collectAllCapsWords(names)
    }

    // MARK: - Re-plan (apply a title/year edit)

    /// Rebuild a node's preview pairs and move operations from its current
    /// `units` (each carrying its own episode code, season, language, and
    /// disambiguation suffix) and the node's current `editTitle`/`editYear`.
    /// Non-move operations (empty-source cleanup) are preserved, in order.
    private static func recompute(_ node: NodePlan, root: URL) -> NodePlan {
        var updated = node
        var pairs: [PreviewPair] = []
        var ops: [Operation] = []
        for unit in node.units {
            let dst = computeDestination(unit, title: node.editTitle, year: node.editYear, root: root)
            pairs.append(PreviewPair(old: relativePath(unit.source, from: root),
                                     new: relativePath(dst, from: root)))
            if unit.source.path != dst.path { ops.append(.move(from: unit.source, to: dst)) }
        }
        // Re-derive the empty-source-folder cleanup from the CURRENT title/year
        // rather than preserving the build-time op: a title/year edit moves the
        // destination folder, so a source folder that *was* the destination may no
        // longer be (and would otherwise be orphaned), or vice-versa. Only
        // folder-backed nodes have a source directory to clean up; loose nodes don't.
        if Scanner.isDirectory(node.source),
           node.source.standardizedFileURL.path
             != destinationFolder(node, root: root).standardizedFileURL.path {
            ops.append(.removeEmptyDirectory(node.source))
        }

        updated.previewPairs = pairs
        updated.operations = ops
        updated.status = ops.contains(where: \.isMove) ? .rename : .unchanged
        return updated
    }

    /// Recompute a node's destinations from an edited title/year. Season and
    /// episode codes stay fixed per file; only the title (and, for movies, the
    /// year) change. Non-move operations (empty-source cleanup) are preserved.
    public static func replan(_ node: NodePlan, title: String, year: String, root: URL) -> NodePlan {
        guard node.status != .skip, !node.units.isEmpty else { return node }
        var updated = node
        updated.editTitle = title
        updated.editYear = year
        return recompute(updated, root: root)
    }

    /// Apply a title/year edit to one item in a plan and re-detect conflicts.
    public static func replan(_ plan: Plan, itemSource: URL, title: String, year: String) -> Plan {
        var nodes = plan.nodes
        if let i = nodes.firstIndex(where: { $0.source == itemSource }) {
            nodes[i] = replan(nodes[i], title: title, year: year, root: plan.root)
        }
        return Plan(root: plan.root, nodes: nodes, conflicts: ConflictChecker.detect(in: nodes))
    }

    /// Apply per-file version labels (keyed by a unit's source URL) to resolve
    /// duplicate targets, then re-detect conflicts. A label of "" clears any
    /// existing suffix, restoring the original destination (and the conflict).
    /// Title/year edits already in the plan are preserved.
    public static func resolve(_ plan: Plan, suffixes: [URL: String]) -> Plan {
        guard !suffixes.isEmpty else { return plan }
        var nodes = plan.nodes
        for i in nodes.indices where nodes[i].status != .skip && !nodes[i].units.isEmpty {
            var touched = false
            for j in nodes[i].units.indices {
                if let label = suffixes[nodes[i].units[j].source] {
                    nodes[i].units[j].disambiguationSuffix = label
                    touched = true
                }
            }
            if touched { nodes[i] = recompute(nodes[i], root: plan.root) }
        }
        return Plan(root: plan.root, nodes: nodes, conflicts: ConflictChecker.detect(in: nodes))
    }

    // MARK: - Loose files

    /// One node for ≥2 loose videos that share a show (TV) or title+year
    /// (movie). Like a subfolder node — one editable title, a `Season N/` split
    /// at the destination — but with no source folder to remove. (Loose sidecars
    /// are not paired here; they remain individual skip nodes, as before.)
    private static func planLooseGroup(_ parses: [(URL, MediaParse)], root: URL) -> NodePlan {
        let sorted = parses.sorted { $0.0.path < $1.0.path }
        let isTV = sorted[0].1.episodeCode != nil
        let title = sorted[0].1.title          // identical across the group by construction
        let (editTitle, editYear) = isTV ? (title, "") : splitMovieTitle(title)

        let units = sorted.map { video, p in
            RenameUnit(source: video, episodeCode: p.episodeCode, season: p.season,
                       languageSuffix: "", ext: Str.splitext(video.lastPathComponent).ext,
                       disambiguationSuffix: p.versionLabel)
        }
        var plan = NodePlan(source: sorted[0].0, mediaType: isTV ? .tv : .movie,
                            status: .rename, editTitle: editTitle, editYear: editYear, units: units)
        let preserved = Set(sorted.flatMap { $0.1.preservedStopwords }).sorted()
        if !preserved.isEmpty {
            plan.verifyTitle = title
            plan.verifyWords = preserved
        }
        return recompute(plan, root: root)
    }

    /// Fold a loose group's videos into an existing subfolder node for the same
    /// show/movie, then recompute its destinations. The folder's own files (and
    /// its empty-source cleanup) are preserved; the loose files move in beside
    /// them, splitting into `Season N/` as usual.
    private static func merge(_ parses: [(URL, MediaParse)], into node: NodePlan, root: URL) -> NodePlan {
        var updated = node
        for (video, p) in parses.sorted(by: { $0.0.path < $1.0.path }) {
            updated.units.append(RenameUnit(
                source: video, episodeCode: p.episodeCode, season: p.season,
                languageSuffix: "", ext: Str.splitext(video.lastPathComponent).ext,
                disambiguationSuffix: p.versionLabel))
        }
        let extra = parses.flatMap { $0.1.preservedStopwords }
        if !extra.isEmpty {
            updated.verifyWords = Set(updated.verifyWords).union(extra).sorted()
            if updated.verifyTitle.isEmpty { updated.verifyTitle = updated.editTitle }
        }
        return recompute(updated, root: root)
    }

    private static func planLoose(_ path: URL, root: URL, parse: MediaParse) -> NodePlan {
        let isTV = parse.episodeCode != nil
        let (title, year) = isTV ? (parse.title, "") : splitMovieTitle(parse.title)
        let unit = RenameUnit(
            source: path, episodeCode: parse.episodeCode, season: parse.season,
            languageSuffix: "", ext: Str.splitext(path.lastPathComponent).ext,
            disambiguationSuffix: parse.versionLabel)

        var plan = NodePlan(source: path, mediaType: isTV ? .tv : .movie, status: .rename,
                            editTitle: title, editYear: year, units: [unit])
        if !parse.preservedStopwords.isEmpty {
            plan.verifyTitle = parse.title
            plan.verifyWords = parse.preservedStopwords
        }

        let dst = computeDestination(unit, title: title, year: year, root: root)
        plan.previewPairs = [PreviewPair(old: relativePath(path, from: root),
                                         new: relativePath(dst, from: root))]
        if path.path == dst.path {
            plan.status = .unchanged
        } else {
            plan.operations.append(.move(from: path, to: dst))
        }
        return plan
    }

    // MARK: - Folders

    private static func planDirectory(_ folder: URL, root: URL,
                                      acronyms: [String: String]) -> NodePlan {
        let (videos, sidecars, junk) = Scanner.scanContents(folder)
        if videos.isEmpty {
            return NodePlan(source: folder, mediaType: .unknown, status: .skip,
                            note: "folder has no .mkv files", junk: junk)
        }

        let parses: [(URL, MediaParse?)] = videos.map { v in
            (v, MediaParser.tv(v.lastPathComponent, acronyms: acronyms)
                ?? MediaParser.movie(v.lastPathComponent, acronyms: acronyms))
        }
        let tvCount = parses.filter { $0.1?.episodeCode != nil }.count
        let movieCount = parses.filter { $0.1 != nil && $0.1?.episodeCode == nil }.count
        let unknownCount = parses.filter { $0.1 == nil }.count

        if (tvCount > 0 && movieCount == 0 && unknownCount == 0)
            || (movieCount > 0 && tvCount == 0 && unknownCount == 0) {
            let homogeneous = parses.compactMap { (v, p) in p.map { (v, $0) } }
            return planFolder(folder, parses: homogeneous,
                              sidecars: sidecars, junk: junk, root: root)
        } else if unknownCount > 0 && tvCount == 0 && movieCount == 0 {
            let offender = parses.first { $0.1 == nil }?.0.lastPathComponent ?? ""
            return NodePlan(source: folder, mediaType: .unknown, status: .skip,
                            note: "file has no episode code or release year: \(offender)",
                            junk: junk)
        } else {
            return NodePlan(source: folder, mediaType: .unknown, status: .skip,
                            note: "mixed TV/movie or unrecognised content "
                                + "(tv=\(tvCount), movie=\(movieCount), unknown=\(unknownCount))",
                            junk: junk)
        }
    }

    private static func planFolder(_ folder: URL, parses: [(URL, MediaParse)],
                                   sidecars: [URL], junk: [URL], root: URL) -> NodePlan {
        let isTV = parses[0].1.episodeCode != nil

        // Most common title, ties broken by first appearance (mirrors Counter).
        var counts: [String: Int] = [:]
        var order: [String] = []
        for (_, p) in parses {
            if counts[p.title] == nil { order.append(p.title) }
            counts[p.title, default: 0] += 1
        }
        var title = order[0]
        var bestCount = counts[title]!
        for t in order.dropFirst() where counts[t]! > bestCount {
            title = t
            bestCount = counts[t]!
        }
        let (editTitle, editYear) = isTV ? (title, "") : splitMovieTitle(title)

        // One unit per output file: the video, then each of its sidecars.
        let sidecarMap = Sidecars.group(videos: parses.map { $0.0 }, sidecars: sidecars)
        var units: [RenameUnit] = []
        for (video, p) in parses {
            units.append(RenameUnit(
                source: video, episodeCode: p.episodeCode, season: p.season,
                languageSuffix: "", ext: Str.splitext(video.lastPathComponent).ext,
                disambiguationSuffix: p.versionLabel))
            // Sidecars inherit their video's version label so they stay paired.
            for s in sidecarMap[video] ?? [] {
                units.append(RenameUnit(
                    source: s, episodeCode: p.episodeCode, season: p.season,
                    languageSuffix: Sidecars.languageSuffix(s.lastPathComponent),
                    ext: Str.splitext(s.lastPathComponent).ext,
                    disambiguationSuffix: p.versionLabel))
            }
        }

        var plan = NodePlan(source: folder, mediaType: isTV ? .tv : .movie,
                            status: .rename, junk: junk,
                            editTitle: editTitle, editYear: editYear, units: units)

        let allPreserved = Set(parses.flatMap { $0.1.preservedStopwords }).sorted()
        if !allPreserved.isEmpty {
            plan.verifyTitle = title
            plan.verifyWords = allPreserved
        }

        for unit in units {
            let dst = computeDestination(unit, title: editTitle, year: editYear, root: root)
            if unit.source.path != dst.path { plan.operations.append(.move(from: unit.source, to: dst)) }
            plan.previewPairs.append(PreviewPair(old: relativePath(unit.source, from: root),
                                                 new: relativePath(dst, from: root)))
        }

        // Remove the now-empty source folder (unless it *is* the destination).
        if folder.standardizedFileURL.path
             != destinationFolder(plan, root: root).standardizedFileURL.path {
            plan.operations.append(.removeEmptyDirectory(folder))
        }

        if !plan.operations.contains(where: \.isMove) { plan.status = .unchanged }
        return plan
    }

    // MARK: - Helpers

    /// The destination URL for one output file given a title/year.
    /// TV: `root/title/Season N/title CODE[ - tag][.lang].ext`.
    /// Movie: `root/title (year)/title (year)[ - tag][.lang].ext`.
    ///
    /// A non-empty `disambiguationSuffix` is rendered as ` - <tag>` on the
    /// filename only — the containing folder is unchanged, so multiple versions
    /// share one `Title (Year)/` folder (Plex/Jellyfin treat them as versions).
    static func computeDestination(_ unit: RenameUnit, title: String, year: String, root: URL) -> URL {
        // Titles, years, and version labels can be edited freely in the UI, so a
        // stray `/`, `:`, or a bare `..` must never escape the chosen root or
        // split a name across directories. Sanitise every user-entered piece
        // before it becomes a path component.
        let tag = sanitizeSeparators(unit.disambiguationSuffix)
        let suffix = tag.isEmpty ? "" : " - \(tag)"
        let safeTitle = pathComponentSafe(title, fallback: "Untitled")
        if let code = unit.episodeCode, let season = unit.season {
            return root.appendingPathComponent(safeTitle)
                .appendingPathComponent("Season \(season)")
                .appendingPathComponent("\(safeTitle) \(code)\(suffix)\(unit.languageSuffix)\(unit.ext)")
        } else {
            // A cleared year drops the empty `()` rather than emitting `Title ()`.
            let safeYear = sanitizeSeparators(year)
            let full = safeYear.isEmpty ? safeTitle : "\(safeTitle) (\(safeYear))"
            return root.appendingPathComponent(full)
                .appendingPathComponent("\(full)\(suffix)\(unit.languageSuffix)\(unit.ext)")
        }
    }

    /// The top-level folder under `root` that a node's files land in — named for
    /// the title (TV) or `Title (Year)` (movie). Mirrors the first path component
    /// of `computeDestination`, and is the folder an emptied source is compared
    /// against to decide on cleanup. Single source of truth for both build
    /// (`planFolder`) and re-plan (`recompute`).
    static func destinationFolder(_ node: NodePlan, root: URL) -> URL {
        let safeTitle = pathComponentSafe(node.editTitle, fallback: "Untitled")
        if node.mediaType == .tv {
            return root.appendingPathComponent(safeTitle)
        }
        let safeYear = sanitizeSeparators(node.editYear)
        let name = safeYear.isEmpty ? safeTitle : "\(safeTitle) (\(safeYear))"
        return root.appendingPathComponent(name)
    }

    /// Replace the characters that would split or redirect a path component
    /// (`/`, `\`, `:`) with `-` and trim surrounding whitespace. Leaves all other
    /// content untouched, so ordinary titles pass through byte-for-byte. Public
    /// so the UI can render a version-label preview that matches the on-disk name.
    public static func sanitizeSeparators(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    /// A user-entered title made safe as a single path component: separators
    /// stripped, and an empty or dot-only name (`""`, `"."`, `".."`) — which
    /// would otherwise vanish or resolve to a parent directory — replaced with
    /// `fallback`.
    static func pathComponentSafe(_ s: String, fallback: String) -> String {
        let c = sanitizeSeparators(s)
        return (c.isEmpty || c.allSatisfy { $0 == "." }) ? fallback : c
    }

    /// Split a movie title `"Name (YYYY)"` into its name and year parts.
    static func splitMovieTitle(_ title: String) -> (name: String, year: String) {
        guard title.hasSuffix(")"), let open = title.lastIndex(of: "(") else {
            return (title, "")
        }
        let year = String(title[title.index(after: open)..<title.index(before: title.endIndex)])
        let name = String(title[..<open]).trimmingCharacters(in: .whitespaces)
        return (name, year)
    }

    /// Path of `url` relative to `root` (both assumed in-tree). Mirrors
    /// `os.path.relpath` for the under-root case.
    static func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.path
        let path = url.path
        if path == rootPath { return "." }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        return path
    }
}
