import Testing
import Foundation
@testable import RenamerCore

/// `PlanBuilder.assemble` is the pure extraction of the app's three-pass rebuild
/// (build → resolve duplicates → re-apply title/year edits). These tests pin the
/// edit-persistence behaviour (#5) that previously lived only in
/// `AppModel.rebuildPlan`, which the app target has no harness to cover.
@Suite("Assemble (rebuild ordering / edit persistence)")
struct AssembleTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-assemble-\(UUID().uuidString)")
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

    /// The core #5 guarantee: a manual title edit SURVIVES an acronym-map change
    /// (which rebuilds the whole plan), while a NON-edited node reflects the new
    /// acronym casing. Two shows whose titles are all-caps acronyms ("NASA",
    /// "FBI"): kept, both stay upper; edit NASA's show name, then flip the map to
    /// title-case everything — NASA keeps the manual name, FBI follows the toggle.
    @Test func titleEditSurvivesAcronymChangeWhileOthersFollowIt() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("NASA.S01E01.mkv"))
        touch(root.appendingPathComponent("FBI.S01E01.mkv"))

        // Acronyms KEPT → both titles stay all-caps.
        let kept = PlanBuilder.assemble(root: root, acronyms: ["NASA": "NASA", "FBI": "FBI"])
        let nasa = node(kept, "NASA.S01E01.mkv")
        let fbi = node(kept, "FBI.S01E01.mkv")
        #expect(nasa.editTitle == "NASA")
        #expect(fbi.editTitle == "FBI")

        // Rename NASA's show, then flip the acronym map to title-case everything
        // (an acronym toggle rebuilds the whole plan from scratch).
        let edits: [URL: (title: String, year: String)] = [nasa.source: ("Space Program", "")]
        let rebuilt = PlanBuilder.assemble(root: root, acronyms: [:], titleEdits: edits)

        // The manual edit survives the rebuild, destinations and all…
        let nasa2 = node(rebuilt, "NASA.S01E01.mkv")
        #expect(nasa2.editTitle == "Space Program")
        #expect(nasa2.previewPairs.map(\.new) == ["Space Program/Season 1/Space Program S01E01.mkv"])

        // …while the NON-edited node reflects the new (title-cased) acronym casing.
        let fbi2 = node(rebuilt, "FBI.S01E01.mkv")
        #expect(fbi2.editTitle == "Fbi")
        #expect(fbi2.previewPairs.map(\.new) == ["Fbi/Season 1/Fbi S01E01.mkv"])
    }

    /// Documents WHY `AppModel.replan` records an edit only on a REAL change.
    /// `assemble` faithfully re-applies every edit it is handed AFTER the acronym
    /// rebuild, so a "phantom" edit equal to the kept-acronym title would re-pin
    /// the old casing and silently veto a title-case toggle — exactly the #5
    /// regression. The guard that stops such an edit ever being recorded lives
    /// UI-side in `AppModel.replan` (reasoning-verified; the app target has no
    /// test harness). This pins the hazard so the guard can't be dropped without
    /// a visible signal here.
    @Test func phantomEditEqualToParsedTitleWouldOverrideAcronym() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("FBI.S01E01.mkv"))

        // No edit recorded → the node follows the acronym map (title-cased).
        let clean = PlanBuilder.assemble(root: root, acronyms: [:])
        let fbiSource = node(clean, "FBI.S01E01.mkv").source
        #expect(node(clean, "FBI.S01E01.mkv").editTitle == "Fbi")

        // A phantom edit equal to the KEPT title re-pins "FBI" and overrides the
        // title-case toggle — which is precisely why replan must not record it.
        let phantom: [URL: (title: String, year: String)] = [fbiSource: ("FBI", "")]
        let pinned = PlanBuilder.assemble(root: root, acronyms: [:], titleEdits: phantom)
        #expect(node(pinned, "FBI.S01E01.mkv").editTitle == "FBI")
    }

    /// `assemble` re-applies version-label disambiguation alongside title edits:
    /// two loose copies of one movie collide, labelling clears it, and a title
    /// edit on the shared node coexists with the labels through the rebuild.
    @Test func assembleAppliesDisambiguationThenEdits() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let hd = root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv")
        let uhd = root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv")
        touch(hd); touch(uhd)

        // Unresolved: the two versions collide on one destination.
        #expect(PlanBuilder.assemble(root: root).conflicts.count == 2)

        let labels = QualityTag.distinctLabels(for: PlanBuilder.assemble(root: root).conflictGroups[0])
        // The two copies share one node (same title+year); edit that node's title.
        let nodeSrc = PlanBuilder.assemble(root: root).nodes.first { $0.mediaType == .movie }!.source
        let edits: [URL: (title: String, year: String)] = [nodeSrc: ("Thing", "1982")]

        let resolved = PlanBuilder.assemble(root: root, disambiguation: labels, titleEdits: edits)
        #expect(resolved.conflicts.isEmpty)
        let movie = resolved.nodes.first { $0.mediaType == .movie }!
        #expect(Set(movie.previewPairs.map(\.new)) == [
            "Thing (1982)/Thing (1982) - 1080p BluRay.mkv",
            "Thing (1982)/Thing (1982) - 2160p BluRay.mkv",
        ])
    }
}
