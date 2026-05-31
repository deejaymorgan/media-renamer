import Foundation

/// Turns an input folder into node plans (and a full `Plan` with conflicts).
/// Ported from `plan_input_dir` / `plan_loose` / `plan_folder`.
public enum PlanBuilder {

    /// Build a full plan (nodes + conflicts) for `root`.
    public static func plan(root: URL, acronyms: [String: String] = [:]) -> Plan {
        let nodes = build(root: root, acronyms: acronyms)
        return Plan(root: root, nodes: nodes, conflicts: ConflictChecker.detect(in: nodes))
    }

    /// One `NodePlan` per top-level entry in `root`.
    public static func build(root: URL, acronyms: [String: String] = [:]) -> [NodePlan] {
        var plans: [NodePlan] = []
        for entry in Scanner.listDir(root) {
            let base = entry.lastPathComponent
            if !Scanner.isDirectory(entry) {
                plans.append(planFile(entry, root: root, acronyms: acronyms))
            } else if Constants.ignoredFolderNames.contains(base.lowercased()) {
                plans.append(NodePlan(source: entry, mediaType: .unknown, status: .skip,
                                      note: "ignored library folder: \(base)"))
            } else {
                plans.append(planDirectory(entry, root: root, acronyms: acronyms))
            }
        }
        return plans
    }

    // MARK: - Re-plan (apply a title/year edit)

    /// Recompute a node's destinations from an edited title/year. Season and
    /// episode codes stay fixed per file; only the title (and, for movies, the
    /// year) change. Non-move operations (empty-source cleanup) are preserved.
    public static func replan(_ node: NodePlan, title: String, year: String, root: URL) -> NodePlan {
        guard node.status != .skip, !node.units.isEmpty else { return node }
        var updated = node
        updated.editTitle = title
        updated.editYear = year

        var pairs: [PreviewPair] = []
        var ops: [Operation] = []
        for unit in node.units {
            let dst = computeDestination(unit, title: title, year: year, root: root)
            pairs.append(PreviewPair(old: relativePath(unit.source, from: root),
                                     new: relativePath(dst, from: root)))
            if unit.source.path != dst.path { ops.append(.move(from: unit.source, to: dst)) }
        }
        for op in node.operations where !op.isMove { ops.append(op) }

        updated.previewPairs = pairs
        updated.operations = ops
        updated.status = ops.contains(where: \.isMove) ? .rename : .unchanged
        return updated
    }

    /// Apply a title/year edit to one item in a plan and re-detect conflicts.
    public static func replan(_ plan: Plan, itemSource: URL, title: String, year: String) -> Plan {
        var nodes = plan.nodes
        if let i = nodes.firstIndex(where: { $0.source == itemSource }) {
            nodes[i] = replan(nodes[i], title: title, year: year, root: plan.root)
        }
        return Plan(root: plan.root, nodes: nodes, conflicts: ConflictChecker.detect(in: nodes))
    }

    // MARK: - Loose files

    private static func planFile(_ entry: URL, root: URL, acronyms: [String: String]) -> NodePlan {
        let base = entry.lastPathComponent
        let ext = Str.splitext(base).ext.lowercased()
        guard Constants.videoExtensions.contains(ext) else {
            return NodePlan(source: entry, mediaType: .unknown, status: .skip,
                            note: "loose non-video file at root")
        }
        guard let parse = MediaParser.tv(base, acronyms: acronyms)
                ?? MediaParser.movie(base, acronyms: acronyms) else {
            return NodePlan(source: entry, mediaType: .unknown, status: .skip,
                            note: "no episode code or release year")
        }
        return planLoose(entry, root: root, parse: parse)
    }

    private static func planLoose(_ path: URL, root: URL, parse: MediaParse) -> NodePlan {
        let isTV = parse.episodeCode != nil
        let (title, year) = isTV ? (parse.title, "") : splitMovieTitle(parse.title)
        let unit = RenameUnit(
            source: path, episodeCode: parse.episodeCode, season: parse.season,
            languageSuffix: "", ext: Str.splitext(path.lastPathComponent).ext)

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
                languageSuffix: "", ext: Str.splitext(video.lastPathComponent).ext))
            for s in sidecarMap[video] ?? [] {
                units.append(RenameUnit(
                    source: s, episodeCode: p.episodeCode, season: p.season,
                    languageSuffix: Sidecars.languageSuffix(s.lastPathComponent),
                    ext: Str.splitext(s.lastPathComponent).ext))
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
        let mediaDir = root.appendingPathComponent(title)
        if folder.standardizedFileURL.path != mediaDir.standardizedFileURL.path {
            plan.operations.append(.removeEmptyDirectory(folder))
        }

        if !plan.operations.contains(where: \.isMove) { plan.status = .unchanged }
        return plan
    }

    // MARK: - Helpers

    /// The destination URL for one output file given a title/year.
    /// TV: `root/title/Season N/title CODE[.lang].ext`.
    /// Movie: `root/title (year)/title (year)[.lang].ext`.
    static func computeDestination(_ unit: RenameUnit, title: String, year: String, root: URL) -> URL {
        if let code = unit.episodeCode, let season = unit.season {
            return root.appendingPathComponent(title)
                .appendingPathComponent("Season \(season)")
                .appendingPathComponent("\(title) \(code)\(unit.languageSuffix)\(unit.ext)")
        } else {
            let full = "\(title) (\(year))"
            return root.appendingPathComponent(full)
                .appendingPathComponent("\(full)\(unit.languageSuffix)\(unit.ext)")
        }
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
