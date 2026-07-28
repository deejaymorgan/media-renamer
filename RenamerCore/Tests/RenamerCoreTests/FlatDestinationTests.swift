import Testing
import Foundation
@testable import RenamerCore

/// The rename-only ("flat") output shape: identical naming rules, no folder tree.
///
/// The whole feature rests on one claim — flattening changes *where* a file goes,
/// never *what it is called*. These tests pin that claim from both ends: the
/// path formula (`computeDestination`) and the assembled plan, always by
/// computing BOTH modes for the same input so a flat expectation can never pass
/// by accident. The one place the two modes legitimately differ in behaviour
/// (rather than in path) is the emptied-source-folder cleanup, which gets its own
/// contrast test below.
@Suite("Flat (rename-only) destinations")
struct FlatDestinationTests {

    private var fm: FileManager { .default }

    /// The cascade every flat plan in this suite uses: flatten everything.
    private var flatCascade: ModeCascade { ModeCascade(global: .renameOnly) }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-flat-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    private func node(_ plan: Plan, _ basename: String) -> NodePlan {
        plan.nodes.first { $0.source.lastPathComponent == basename }!
    }

    private func moveTargets(_ n: NodePlan) -> [URL] {
        n.operations.compactMap { (op: RenamerCore.Operation) -> URL? in
            if case let .move(_, to) = op { return to }
            return nil
        }
    }

    private func cleanupTargets(_ n: NodePlan) -> [URL] {
        n.operations.compactMap { (op: RenamerCore.Operation) -> URL? in
            if case let .removeEmptyDirectory(dir) = op { return dir }
            return nil
        }
    }

    /// Is `url` a direct child of `root` — i.e. nothing between it and the root?
    /// This is the whole of "flat", expressed as a predicate.
    private func isDirectChild(_ url: URL, of root: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path
    }

    /// The filename part of a root-relative preview path.
    private func leaf(_ pair: PreviewPair) -> String {
        String(pair.new.split(separator: "/").last ?? "")
    }

    private func paths(_ urls: [URL]) -> [String] { urls.map(\.standardizedFileURL.path) }

    // MARK: - The four shapes

    /// A TV show flattens *both* levels away: neither the `Show Name/` folder nor
    /// the `Season N/` split survives. Two seasons in one source folder make that
    /// visible — in organise mode they diverge into two different season folders,
    /// in flat mode they sit side by side in the root, which is the arrangement a
    /// user who picked rename-only actually asked for.
    @Test func tvEpisodesLandDirectlyInTheRootWithNoSeasonSplit() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Severance.COMPLETE")
        touch(folder.appendingPathComponent("Severance.S01E01.1080p.WEB-DL.mkv"))
        touch(folder.appendingPathComponent("Severance.S02E03.1080p.WEB-DL.mkv"))

        let flat = node(PlanBuilder.assemble(root: root, cascade: flatCascade), "Severance.COMPLETE")
        #expect(flat.outputMode == .renameOnly)
        #expect(Set(flat.previewPairs.map(\.new)) == [
            "Severance S01E01.mkv",
            "Severance S02E03.mkv",
        ])
        // Not one path separator anywhere: no `Severance/`, no `Season N/`.
        #expect(flat.previewPairs.allSatisfy { !$0.new.contains("/") })
        #expect(moveTargets(flat).allSatisfy { isDirectChild($0, of: root) })

        // The same fixture in organise mode DOES build the two-level tree, so the
        // flat result above is the mode's doing and not a quirk of the input.
        let organised = node(PlanBuilder.assemble(root: root), "Severance.COMPLETE")
        #expect(Set(organised.previewPairs.map(\.new)) == [
            "Severance/Season 1/Severance S01E01.mkv",
            "Severance/Season 2/Severance S02E03.mkv",
        ])
    }

    /// A movie loses its `Movie Name (Year)/` wrapper but keeps the year in the
    /// filename — the year is part of the name Plex matches on, not merely a
    /// property of the folder, so flattening must not shed it.
    @Test func movieLandsDirectlyInTheRootKeepingItsYear() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Inception.2010.1080p.BluRay.x264-GROUP")
        touch(folder.appendingPathComponent("Inception.2010.1080p.BluRay.x264-GROUP.mkv"))

        let flat = node(PlanBuilder.assemble(root: root, cascade: flatCascade),
                        "Inception.2010.1080p.BluRay.x264-GROUP")
        #expect(flat.previewPairs.map(\.new) == ["Inception (2010).mkv"])
        #expect(moveTargets(flat).count == 1)
        #expect(moveTargets(flat).allSatisfy { isDirectChild($0, of: root) })

        let organised = node(PlanBuilder.assemble(root: root),
                             "Inception.2010.1080p.BluRay.x264-GROUP")
        #expect(organised.previewPairs.map(\.new) == ["Inception (2010)/Inception (2010).mkv"])
    }

    /// A subtitle sidecar keeps its recognised language sub-extension in flat mode
    /// and stays adjacent to its video. Pairing is what makes a sidecar work at
    /// all — a player finds subtitles by matching the video's stem — so a flat
    /// layout that renamed the video but not (or differently) its `.eng.srt`
    /// would silently orphan the subtitles.
    @Test func sidecarKeepsItsLanguageSuffixAndStaysPairedWithItsVideo() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Severance.S01.1080p.WEB-DL")
        touch(folder.appendingPathComponent("Severance.S01E01.1080p.WEB-DL.mkv"))
        touch(folder.appendingPathComponent("Severance.S01E01.1080p.WEB-DL.eng.srt"))

        let flat = node(PlanBuilder.assemble(root: root, cascade: flatCascade),
                        "Severance.S01.1080p.WEB-DL")
        // Ordered: the sidecar follows its video, and both share one stem.
        #expect(flat.previewPairs.map(\.new) == [
            "Severance S01E01.mkv",
            "Severance S01E01.eng.srt",
        ])
        #expect(moveTargets(flat).count == 2)
        #expect(moveTargets(flat).allSatisfy { isDirectChild($0, of: root) })

        // In organise mode the pair shares a season folder; flattening moves the
        // pair, not just the video.
        let organised = node(PlanBuilder.assemble(root: root), "Severance.S01.1080p.WEB-DL")
        #expect(organised.previewPairs.map(\.new) == [
            "Severance/Season 1/Severance S01E01.mkv",
            "Severance/Season 1/Severance S01E01.eng.srt",
        ])
    }

    /// Two versions of one movie collide in flat mode exactly as they do in
    /// organise mode (the destination filename is the same, so the collision is
    /// the same), and the resolver's ` - <label>` tail survives flattening. Losing
    /// the tail here would turn a resolved pair back into a silent overwrite.
    @Test func versionLabelSurvivesFlattening() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv"))
        touch(root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv"))

        // Flattening neither invents nor hides collisions.
        let unresolved = PlanBuilder.assemble(root: root, cascade: flatCascade)
        #expect(unresolved.conflicts.count == 2)
        #expect(unresolved.conflictGroups.count == 1)

        let labels = QualityTag.distinctLabels(for: unresolved.conflictGroups[0])
        let resolved = PlanBuilder.assemble(root: root, cascade: flatCascade, disambiguation: labels)
        #expect(resolved.conflicts.isEmpty)

        // The two copies share a title+year and so share one node.
        let movie = resolved.nodes.first { $0.mediaType == .movie }!
        #expect(Set(movie.previewPairs.map(\.new)) == [
            "The Thing (1982) - 1080p BluRay.mkv",
            "The Thing (1982) - 2160p BluRay.mkv",
        ])
        #expect(moveTargets(movie).allSatisfy { isDirectChild($0, of: root) })

        // Organise mode puts the very same two filenames inside one shared folder —
        // only the wrapper differs.
        let organised = PlanBuilder.assemble(root: root, disambiguation: labels)
            .nodes.first { $0.mediaType == .movie }!
        #expect(Set(organised.previewPairs.map(\.new)) == [
            "The Thing (1982)/The Thing (1982) - 1080p BluRay.mkv",
            "The Thing (1982)/The Thing (1982) - 2160p BluRay.mkv",
        ])
    }

    // MARK: - The key property: only the containing path changes

    /// The load-bearing invariant, as a general property rather than four
    /// coincidences: for every shape the formula can produce — TV, movie, sidecar
    /// language codes, version labels, a cleared year, a title needing
    /// sanitisation — the two modes emit a **byte-identical filename**, the flat
    /// one is a direct child of the root, and the organise one is that same name
    /// wrapped in strictly more path components.
    ///
    /// This is why flattening introduces no new class of collision (the conflict
    /// checker compares destination paths, and the leaf never moves) and why the
    /// mode can be toggled in the UI without re-deriving any name. If someone ever
    /// gives the flat branch its own name-building code, this table is what fails.
    @Test func filenameIsByteIdenticalInBothModes() {
        // `computeDestination` is pure string work — it never touches the disk and
        // never reads `unit.source` — so a synthetic root keeps this deterministic.
        let root = URL(fileURLWithPath: "/Volumes/Media/Inbox")
        let anySource = root.appendingPathComponent("whatever.mkv")

        let table: [(label: String, unit: RenameUnit, title: String, year: String, name: String)] = [
            ("TV episode",
             RenameUnit(source: anySource, episodeCode: "S01E01", season: 1,
                        languageSuffix: "", ext: ".mkv"),
             "Severance", "", "Severance S01E01.mkv"),

            ("TV sidecar with a language code",
             RenameUnit(source: anySource, episodeCode: "S01E01", season: 1,
                        languageSuffix: ".eng", ext: ".srt"),
             "Severance", "", "Severance S01E01.eng.srt"),

            ("TV with a version label",
             RenameUnit(source: anySource, episodeCode: "S02E03", season: 2,
                        languageSuffix: "", ext: ".mkv", disambiguationSuffix: "1080p WEB-DL"),
             "Severance", "", "Severance S02E03 - 1080p WEB-DL.mkv"),

            ("Movie",
             RenameUnit(source: anySource, episodeCode: nil, season: nil,
                        languageSuffix: "", ext: ".mkv"),
             "Inception", "2010", "Inception (2010).mkv"),

            ("Movie sidecar with a language code",
             RenameUnit(source: anySource, episodeCode: nil, season: nil,
                        languageSuffix: ".fre", ext: ".srt"),
             "Inception", "2010", "Inception (2010).fre.srt"),

            ("Movie with a version label",
             RenameUnit(source: anySource, episodeCode: nil, season: nil,
                        languageSuffix: "", ext: ".mkv", disambiguationSuffix: "2160p Remux"),
             "Inception", "2010", "Inception (2010) - 2160p Remux.mkv"),

            ("Movie with a cleared year",
             RenameUnit(source: anySource, episodeCode: nil, season: nil,
                        languageSuffix: "", ext: ".mkv"),
             "Inception", "", "Inception.mkv"),

            ("Title carrying path separators",
             RenameUnit(source: anySource, episodeCode: nil, season: nil,
                        languageSuffix: "", ext: ".mkv"),
             "AC/DC: Live", "1991", "AC-DC- Live (1991).mkv"),
        ]

        for row in table {
            let flat = PlanBuilder.computeDestination(row.unit, title: row.title, year: row.year,
                                                      root: root, mode: .renameOnly)
            let organised = PlanBuilder.computeDestination(row.unit, title: row.title, year: row.year,
                                                           root: root, mode: .organise)

            // The name itself — pinned literally, then pinned as equal across modes.
            #expect(flat.lastPathComponent == row.name, "\(row.label)")
            #expect(organised.lastPathComponent == flat.lastPathComponent, "\(row.label)")

            // Flat means: directly in the root, nothing in between.
            #expect(isDirectChild(flat, of: root), "\(row.label)")

            // Organise is the same leaf under strictly more folders — so the two
            // modes really are different code paths, and the equality above is not
            // vacuously true.
            #expect(organised.path.hasSuffix("/" + flat.lastPathComponent), "\(row.label)")
            #expect(organised.pathComponents.count > flat.pathComponents.count, "\(row.label)")
            #expect(organised.path != flat.path, "\(row.label)")
        }
    }

    /// The same invariant at whole-plan level, over a mixed tree assembled twice.
    /// Every node keeps its sources, its unit order and its filenames; only the
    /// folders around them change — flat previews carry no separator, organise
    /// previews always do. Node-level rather than formula-level, because this is
    /// what the preview list and the confirmation dialog actually show.
    @Test func flatteningChangesOnlyTheContainingPathAcrossAWholePlan() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let show = root.appendingPathComponent("Severance.S01.1080p.WEB-DL")
        touch(show.appendingPathComponent("Severance.S01E01.1080p.WEB-DL.mkv"))
        touch(show.appendingPathComponent("Severance.S01E01.1080p.WEB-DL.eng.srt"))
        let movie = root.appendingPathComponent("Inception.2010.1080p.BluRay")
        touch(movie.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))
        touch(root.appendingPathComponent("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv"))

        let organised = PlanBuilder.assemble(root: root)
        let flat = PlanBuilder.assemble(root: root, cascade: flatCascade)

        // Same nodes, in the same order — the mode is a layout choice, not a
        // different way of grouping the input.
        #expect(organised.nodes.map(\.source) == flat.nodes.map(\.source))
        let renaming = organised.nodes.filter { !$0.previewPairs.isEmpty }
        #expect(renaming.count == 3)   // guards against an empty, vacuous loop below

        for (o, f) in zip(organised.nodes, flat.nodes) where !o.previewPairs.isEmpty {
            #expect(f.outputMode == .renameOnly)
            #expect(o.previewPairs.map(\.old) == f.previewPairs.map(\.old))
            #expect(o.previewPairs.map { leaf($0) } == f.previewPairs.map { leaf($0) })
            #expect(f.previewPairs.allSatisfy { !$0.new.contains("/") })
            #expect(o.previewPairs.allSatisfy { $0.new.contains("/") })
        }
    }

    // MARK: - Where the two modes legitimately differ

    /// Flat mode ALWAYS offers the emptied source folder for removal, and the
    /// sharpest case is the one organise mode leaves alone. A folder already named
    /// `Movie Name (Year)` holding `Movie Name (Year).mkv` *is* its own organise
    /// destination: nothing moves, nothing is cleaned up, the node is `.unchanged`.
    /// Flat mode pulls that file up to the root, which empties the folder — so the
    /// cleanup op must now appear where organise mode had none. Getting this wrong
    /// leaves a litter of empty folders behind exactly the files the user asked to
    /// flatten. (`destinationFolder` returns the root itself in flat mode, and a
    /// source subfolder is never the root, so the test always holds.)
    @Test func flatModeAlwaysRemovesTheEmptiedSourceFolder() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        // (a) An ordinary scene folder — both modes empty it, both clean it up.
        let scene = root.appendingPathComponent("Severance.S01.1080p.WEB-DL")
        touch(scene.appendingPathComponent("Severance.S01E01.1080p.WEB-DL.mkv"))
        // (b) A folder that is ALREADY exactly what organise mode would build.
        let settled = root.appendingPathComponent("Inception (2010)")
        touch(settled.appendingPathComponent("Inception (2010).mkv"))

        let organised = PlanBuilder.assemble(root: root)
        let flat = PlanBuilder.assemble(root: root, cascade: flatCascade)

        // (a) No contrast — the scene folder is orphaned either way.
        #expect(paths(cleanupTargets(node(organised, scene.lastPathComponent)))
                == [scene.standardizedFileURL.path])
        #expect(paths(cleanupTargets(node(flat, scene.lastPathComponent)))
                == [scene.standardizedFileURL.path])

        // (b) The contrast. Organise mode: this node has literally nothing to do.
        let settledOrganised = node(organised, "Inception (2010)")
        #expect(settledOrganised.status == .unchanged)
        #expect(settledOrganised.operations.isEmpty)

        // Flat mode: the file is pulled up to the root and the folder must go.
        let settledFlat = node(flat, "Inception (2010)")
        #expect(settledFlat.status == .rename)
        #expect(settledFlat.previewPairs.map(\.new) == ["Inception (2010).mkv"])
        #expect(paths(cleanupTargets(settledFlat)) == [settled.standardizedFileURL.path])
        // Cleanup is emitted after the moves — the folder is only empty by then.
        #expect(settledFlat.operations.last?.isMove == false)
    }

    /// The nested case — the one a user most often reaches for rename-only with:
    /// a source folder that is itself already a tree (`Show/Season N/ep.mkv`).
    /// Offering only the top folder for removal would leave it holding an empty
    /// `Season N/`, and `Executor` — which removes a directory only when it is
    /// genuinely empty — would then decline to remove the top folder either, so
    /// flattening would dissolve nothing at all. Asserted end-to-end on a real
    /// temp tree, because the op list alone doesn't prove the folders actually go.
    @Test func flatteningANestedTreeLeavesNoDirectoriesBehind() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let show = root.appendingPathComponent("Severance")
        let s1 = show.appendingPathComponent("Season 1")
        let s2 = show.appendingPathComponent("Season 2")
        touch(s1.appendingPathComponent("Severance.S01E01.1080p.WEB-DL.mkv"))
        touch(s2.appendingPathComponent("Severance.S02E03.1080p.WEB-DL.mkv"))

        let flat = PlanBuilder.assemble(root: root, cascade: flatCascade)
        let n = node(flat, "Severance")
        #expect(Set(n.previewPairs.map(\.new)) == ["Severance S01E01.mkv", "Severance S02E03.mkv"])

        // Every vacated directory is offered, deepest first — an inner folder has
        // to be emptied before its parent can be tested for emptiness.
        #expect(paths(cleanupTargets(n)) == [s1, s2, show].map(\.standardizedFileURL.path))

        let result = Executor.apply(flat)
        #expect(result.movedCount == 2)
        #expect(result.errorCount == 0)
        // The proof: two files at the root and not one directory left standing.
        #expect(Set(Scanner.listDir(root).map(\.lastPathComponent))
                == ["Severance S01E01.mkv", "Severance S02E03.mkv"])
        #expect(!Scanner.isDirectory(show))
    }

    /// The mirror of the above in organise mode: the same nested tree renames each
    /// file *within* its own season folder, so nothing is vacated and no cleanup is
    /// offered. Pins that the cleanup walk follows what actually moves out rather
    /// than blanket-listing every directory it passes — otherwise a plan would
    /// advertise removals it can never perform, and the confirmation dialog's
    /// folder count would overstate the damage.
    @Test func organiseModeOffersNoCleanupWhenFilesRenameInPlace() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let show = root.appendingPathComponent("Severance")
        touch(show.appendingPathComponent("Season 1/Severance.S01E01.1080p.WEB-DL.mkv"))

        let n = node(PlanBuilder.assemble(root: root), "Severance")
        #expect(n.previewPairs.map(\.new) == ["Severance/Season 1/Severance S01E01.mkv"])
        #expect(n.status == .rename)          // the filename does change
        #expect(cleanupTargets(n).isEmpty)    // …but no folder is emptied by it
    }

    /// Flat mode is idempotent for a file that is already flat and already
    /// correctly named: it is exactly where flat mode wants it, so the node is
    /// `.unchanged` and emits no move. Without this, re-running on a
    /// previously-flattened library would churn every file through a
    /// move-onto-itself — the kind of no-op work that Apply should never schedule.
    /// Organise mode, given the identical input, does have work to do, which is
    /// what makes the flat expectation meaningful.
    @Test func alreadyFlatCorrectlyNamedFilesAreUnchanged() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Severance S01E01.mkv"))
        touch(root.appendingPathComponent("Inception (2010).mkv"))

        let flat = PlanBuilder.assemble(root: root, cascade: flatCascade)
        #expect(flat.nodes.count == 2)
        #expect(flat.nodes.allSatisfy { $0.status == .unchanged })
        #expect(flat.nodes.allSatisfy { $0.operations.isEmpty })
        #expect(flat.conflicts.isEmpty)
        // The preview still shows each file, mapping it onto its own name.
        #expect(Set(flat.nodes.flatMap { $0.previewPairs }.map(\.new))
                == ["Severance S01E01.mkv", "Inception (2010).mkv"])
        #expect(flat.nodes.allSatisfy { n in n.previewPairs.allSatisfy { $0.old == $0.new } })

        // Same two files, organise mode: both would be moved into folders.
        let organised = PlanBuilder.assemble(root: root)
        #expect(organised.nodes.allSatisfy { $0.status == .rename })
        #expect(Set(organised.nodes.flatMap { $0.previewPairs }.map(\.new)) == [
            "Severance/Season 1/Severance S01E01.mkv",
            "Inception (2010)/Inception (2010).mkv",
        ])
    }
}
