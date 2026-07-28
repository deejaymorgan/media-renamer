import Testing
import Foundation
@testable import RenamerCore

/// Output mode is the FOURTH replay layer in `PlanBuilder.assemble`: build →
/// stamp modes → resolve duplicates → re-apply title/year edits. These tests pin
/// that the layers COMPOSE — a flat node stays flat through an acronym rebuild,
/// and labels and title edits land on flat names rather than dragging the folder
/// tree back.
///
/// Why the mode is stamped BEFORE disambiguation and title edits: both `resolve`
/// and `replan` funnel through `recompute`, which builds each destination from
/// `node.outputMode`. Stamp the mode afterwards and those layers have already
/// computed destinations for the wrong shape — the conflicts they re-detect, the
/// empty-source cleanup they derive, and the plan a caller reads back between
/// layers would all describe a tree the user never asked for.
///
/// Note what that does *not* mean: seen only through `assemble`, the ordering is
/// not observable. Every layer rebuilds destinations from the node's stored
/// state, so the returned plan is identical whichever order they run in — swap
/// the calls and this suite still passes. The ordering earns its keep because the
/// app calls `resolve`/`replan` **directly on a stored plan** (to offer labels, to
/// accept an edit) rather than re-assembling for every keystroke, so the
/// intermediate plan is a state the UI genuinely renders. That is what
/// `layersDrivenByHandPreserveTheStampedMode` pins.
@Suite("Mode replay (assemble ordering)")
struct ModeReplayTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-mode-replay-\(UUID().uuidString)")
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

    /// The mode counterpart of the #5 edit-persistence guarantee: an acronym
    /// toggle rebuilds the whole plan from scratch, so a mode chosen before the
    /// toggle only survives because `assemble` re-stamps the SAME cascade on the
    /// fresh nodes. The title must still follow the new acronym casing — the two
    /// settings are independent, and neither may swallow the other.
    @Test func flatModeSurvivesAnAcronymRebuild() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("NASA.S01E01.mkv"))

        let flat = ModeCascade(global: .renameOnly)

        // Acronym KEPT: flat destination, all-caps title.
        let kept = PlanBuilder.assemble(root: root, acronyms: ["NASA": "NASA"], cascade: flat)
        let first = node(kept, "NASA.S01E01.mkv")
        #expect(first.outputMode == .renameOnly)
        #expect(first.previewPairs.map(\.new) == ["NASA S01E01.mkv"])

        // Flip the acronym map to title-case everything (a full rebuild), handing
        // back the same cascade: still flat, now title-cased.
        let rebuilt = PlanBuilder.assemble(root: root, acronyms: [:], cascade: flat)
        let second = node(rebuilt, "NASA.S01E01.mkv")
        #expect(second.outputMode == .renameOnly)
        #expect(second.previewPairs.map(\.new) == ["Nasa S01E01.mkv"])

        // Control: the identical rebuild with the DEFAULT cascade keeps the folder
        // tree, so the flat names above are the cascade's doing and this test
        // could not pass with mode support removed.
        let organised = PlanBuilder.assemble(root: root, acronyms: [:])
        #expect(node(organised, "NASA.S01E01.mkv").previewPairs.map(\.new)
                == ["Nasa/Season 1/Nasa S01E01.mkv"])
    }

    /// A title edit is replayed AFTER the mode is stamped, so `replan`'s
    /// recompute sees `.renameOnly` and rebuilds a flat destination. Were the
    /// order reversed, the edited node would come back wearing a `Show/Season N/`
    /// tree the user had already switched off. The move OPERATION is checked as
    /// well as the preview string: the preview is what the user reads, but the
    /// operation is what Apply executes, and only the latter can orphan a file.
    @Test func flatModeComposesWithATitleEdit() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("NASA.S01E01.mkv"))

        let flat = ModeCascade(global: .renameOnly)
        let probe = PlanBuilder.assemble(root: root, cascade: flat)
        let source = node(probe, "NASA.S01E01.mkv").source

        let edits: [URL: (title: String, year: String)] = [source: ("Space Program", "")]
        let edited = PlanBuilder.assemble(root: root, cascade: flat, titleEdits: edits)

        let show = node(edited, "NASA.S01E01.mkv")
        #expect(show.editTitle == "Space Program")
        #expect(show.outputMode == .renameOnly)
        #expect(show.previewPairs.map(\.new) == ["Space Program S01E01.mkv"])

        let moveTargets: [URL] = show.operations.compactMap { (op: RenamerCore.Operation) -> URL? in
            if case .move(_, let to) = op { return to }
            return nil
        }
        #expect(moveTargets == [root.appendingPathComponent("Space Program S01E01.mkv")])
    }

    /// Version labels are replayed after the mode too. Two versions of one movie
    /// collide just as hard when flattened (the filename is identical in both
    /// modes — only the containing path differs), and labelling must clear that
    /// collision with the ` - <label>` suffix landing on the FLAT name. A label
    /// computed against a folder-shaped plan and then flattened would still name
    /// the files correctly, but the conflict state the user is shown in between
    /// would be describing the wrong layout.
    @Test func flatModeComposesWithVersionLabels() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv"))
        touch(root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv"))

        let flat = ModeCascade(global: .renameOnly)

        // Flattening does not dodge the duplicate — both copies still target one name.
        let collided = PlanBuilder.assemble(root: root, cascade: flat)
        #expect(collided.conflicts.count == 2)
        #expect(collided.conflictGroups.count == 1)

        let labels = QualityTag.distinctLabels(for: collided.conflictGroups[0])
        let resolved = PlanBuilder.assemble(root: root, cascade: flat, disambiguation: labels)
        #expect(resolved.conflicts.isEmpty)

        let movie = resolved.nodes.first { $0.mediaType == .movie }!
        #expect(movie.outputMode == .renameOnly)
        #expect(Set(movie.previewPairs.map(\.new)) == [
            "The Thing (1982) - 1080p BluRay.mkv",
            "The Thing (1982) - 2160p BluRay.mkv",
        ])
    }

    /// All four layers in one call — acronyms, mode, labels, title edit — which is
    /// exactly the shape of the app's rebuild after a user has touched every
    /// control. Asserted on the whole plan's destinations rather than one node's,
    /// so a stray folder-shaped path appearing anywhere fails the test.
    ///
    /// The third file exists to make the acronym layer participate: `NASA` collides
    /// with nothing and is never edited, so the only thing that can keep it
    /// all-caps is the acronym map surviving alongside a labelled node and an
    /// edited one. Without it the map would be empty and this would pin three
    /// layers while claiming four.
    @Test func modeLabelsAndTitleEditComposeInOneAssemble() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv"))
        touch(root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv"))
        touch(root.appendingPathComponent("NASA.S01E01.mkv"))

        let flat = ModeCascade(global: .renameOnly)
        let acronyms = ["NASA": "NASA"]
        // The probe must use the same inputs, since the labels and the edit key are
        // both read off it.
        let probe = PlanBuilder.assemble(root: root, acronyms: acronyms, cascade: flat)
        #expect(probe.conflictGroups.count == 1)
        let labels = QualityTag.distinctLabels(for: probe.conflictGroups[0])
        // Both copies share one node (same title+year), so one edit covers both.
        let nodeSource = probe.nodes.first { $0.mediaType == .movie }!.source
        let edits: [URL: (title: String, year: String)] = [nodeSource: ("Thing", "1982")]

        let final = PlanBuilder.assemble(root: root, acronyms: acronyms, cascade: flat,
                                         disambiguation: labels, titleEdits: edits)
        #expect(final.conflicts.isEmpty)
        #expect(final.nodes.allSatisfy { $0.outputMode == .renameOnly })
        #expect(Set(final.nodes.flatMap { $0.previewPairs.map(\.new) }) == [
            "Thing (1982) - 1080p BluRay.mkv",
            "Thing (1982) - 2160p BluRay.mkv",
            "NASA S01E01.mkv",     // `Nasa …` here would mean the acronym map was lost
        ])
    }

    /// What "stamped FIRST" actually buys, pinned where it is observable.
    ///
    /// Driven through `assemble` alone the ordering is invisible: every layer
    /// funnels through `recompute`, which rebuilds destinations from the node's
    /// stored state, so the final plan is the same whichever order they run in.
    /// The ordering matters because the app does not go through `assemble` for
    /// every interaction — it calls `resolve` and `replan` directly on the plan it
    /// is holding. So the property worth pinning is the one those calls rely on:
    /// once a plan has been stamped, each later layer preserves the flat shape,
    /// and the intermediate plan the UI renders between them already describes it.
    @Test func layersDrivenByHandPreserveTheStampedMode() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv"))
        touch(root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv"))

        // 1 · Built, then stamped. The stamped plan is already flat — conflicts and
        //     all — before any label or edit has been applied.
        let built = PlanBuilder.plan(root: root)
        let stamped = PlanBuilder.applyModes(built, cascade: ModeCascade(global: .renameOnly))
        #expect(stamped.nodes.allSatisfy { $0.outputMode == .renameOnly })
        #expect(stamped.nodes.flatMap { $0.previewPairs.map(\.new) }.allSatisfy { !$0.contains("/") })
        #expect(stamped.conflicts.count == 2)
        #expect(stamped.conflictGroups.count == 1)

        // 2 · `resolve` on the already-stamped plan keeps it flat.
        let resolved = PlanBuilder.resolve(stamped,
                                           suffixes: QualityTag.distinctLabels(for: stamped.conflictGroups[0]))
        #expect(resolved.conflicts.isEmpty)
        #expect(resolved.nodes.allSatisfy { $0.outputMode == .renameOnly })
        #expect(Set(resolved.nodes.flatMap { $0.previewPairs.map(\.new) }) == [
            "The Thing (1982) - 1080p BluRay.mkv",
            "The Thing (1982) - 2160p BluRay.mkv",
        ])

        // 3 · …and so does `replan`. Either call resetting `outputMode`, or
        //     recomputing against `.organise`, would surface here rather than being
        //     masked by a re-stamp on the next full assemble.
        let movieSource = resolved.nodes.first { $0.mediaType == .movie }!.source
        let edited = PlanBuilder.replan(resolved, itemSource: movieSource, title: "Thing", year: "1982")
        #expect(edited.nodes.allSatisfy { $0.outputMode == .renameOnly })
        #expect(Set(edited.nodes.flatMap { $0.previewPairs.map(\.new) }) == [
            "Thing (1982) - 1080p BluRay.mkv",
            "Thing (1982) - 2160p BluRay.mkv",
        ])
    }

    /// The cascade resolves per node, not per plan: an item override flattens the
    /// show it names and leaves everything else organised. This mixed plan is the
    /// case the UI has to render — one sidebar list holding nodes of both shapes —
    /// so it is worth pinning in the engine rather than trusting the app to
    /// re-derive it.
    @Test func perItemOverrideBeatsGlobalForThatNodeOnly() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("NASA.S01E01.mkv"))
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))

        // The override is keyed by the node's source URL, so take it from a plan.
        let probe = PlanBuilder.assemble(root: root)
        let tvSource = node(probe, "NASA.S01E01.mkv").source

        let mixed = PlanBuilder.assemble(
            root: root, cascade: ModeCascade(global: .organise, items: [tvSource: .renameOnly]))

        let show = node(mixed, "NASA.S01E01.mkv")
        #expect(show.outputMode == .renameOnly)
        #expect(show.previewPairs.map(\.new) == ["Nasa S01E01.mkv"])

        // The unnamed node is untouched by the override and keeps its folder.
        let movie = node(mixed, "Inception.2010.1080p.BluRay.mkv")
        #expect(movie.outputMode == .organise)
        #expect(movie.previewPairs.map(\.new) == ["Inception (2010)/Inception (2010).mkv"])
    }

    /// The middle rung of the cascade: "all TV" flattens every TV node — loose
    /// files and folder-backed nodes alike — while movies keep inheriting the
    /// global. Two TV nodes of different provenance are used deliberately, since
    /// a group override that only reached loose nodes would still satisfy a
    /// single-file test.
    @Test func groupOverrideFlattensTVAndLeavesMoviesOrganised() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Breaking.Bad.S01E01.mkv"))
        touch(root.appendingPathComponent("The Wire/The.Wire.S02E03.mkv"))
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))

        let plan = PlanBuilder.assemble(
            root: root, cascade: ModeCascade(global: .organise, tv: .renameOnly))

        let tvNodes = plan.nodes.filter { $0.mediaType == .tv }
        #expect(tvNodes.count == 2)
        #expect(tvNodes.allSatisfy { $0.outputMode == .renameOnly })
        #expect(Set(tvNodes.flatMap { $0.previewPairs.map(\.new) }) == [
            "Breaking Bad S01E01.mkv",
            "The Wire S02E03.mkv",
        ])

        let movie = node(plan, "Inception.2010.1080p.BluRay.mkv")
        #expect(movie.outputMode == .organise)
        #expect(movie.previewPairs.map(\.new) == ["Inception (2010)/Inception (2010).mkv"])
    }
}
