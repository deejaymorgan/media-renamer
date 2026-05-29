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
        let dst: URL
        if isTV, let code = parse.episodeCode, let season = parse.season {
            dst = root.appendingPathComponent(parse.title)
                .appendingPathComponent("Season \(season)")
                .appendingPathComponent("\(parse.title) \(code).mkv")
        } else {
            dst = root.appendingPathComponent(parse.title)
                .appendingPathComponent("\(parse.title).mkv")
        }

        var plan = NodePlan(source: path, mediaType: isTV ? .tv : .movie, status: .rename)
        if !parse.preservedStopwords.isEmpty {
            plan.verifyTitle = parse.title
            plan.verifyWords = parse.preservedStopwords
        }
        plan.previewPairs = [PreviewPair(old: relativePath(path, from: root),
                                         new: relativePath(dst, from: root))]
        if path.path == dst.path {
            plan.status = .unchanged
            return plan
        }
        plan.operations.append(.move(from: path, to: dst))
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
        var plan = NodePlan(source: folder, mediaType: isTV ? .tv : .movie,
                            status: .rename, junk: junk)

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

        let allPreserved = Set(parses.flatMap { $0.1.preservedStopwords }).sorted()
        if !allPreserved.isEmpty {
            plan.verifyTitle = title
            plan.verifyWords = allPreserved
        }

        let mediaDir = root.appendingPathComponent(title)
        let sidecarMap = Sidecars.group(videos: parses.map { $0.0 }, sidecars: sidecars)

        for (video, p) in parses {
            let destDir: URL
            let targetStem: String
            if let code = p.episodeCode, let season = p.season {
                destDir = mediaDir.appendingPathComponent("Season \(season)")
                targetStem = "\(title) \(code)"
            } else {
                destDir = mediaDir
                targetStem = title
            }

            let dst = destDir.appendingPathComponent("\(targetStem).mkv")
            if video.path != dst.path { plan.operations.append(.move(from: video, to: dst)) }
            plan.previewPairs.append(PreviewPair(old: relativePath(video, from: root),
                                                 new: relativePath(dst, from: root)))

            for s in sidecarMap[video] ?? [] {
                let sName = Sidecars.newName(targetStem: targetStem, source: s.lastPathComponent)
                let sDst = destDir.appendingPathComponent(sName)
                if s.path != sDst.path { plan.operations.append(.move(from: s, to: sDst)) }
                plan.previewPairs.append(PreviewPair(old: relativePath(s, from: root),
                                                     new: relativePath(sDst, from: root)))
            }
        }

        // Remove the now-empty source folder (unless it *is* the destination).
        if folder.standardizedFileURL.path != mediaDir.standardizedFileURL.path {
            plan.operations.append(.removeEmptyDirectory(folder))
        }

        let hasMove = plan.operations.contains {
            if case .move = $0 { return true } else { return false }
        }
        if !hasMove { plan.status = .unchanged }
        return plan
    }

    // MARK: - Helpers

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
