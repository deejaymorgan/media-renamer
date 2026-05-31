import Testing
import Foundation
@testable import RenamerCore

/// Re-plan (editing a title/year) recomputes destinations from the stored units.
@Suite("Re-plan (edit title/year)")
struct ReplanTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-replan-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    private func node(_ nodes: [NodePlan], _ basename: String) -> NodePlan? {
        nodes.first { $0.source.lastPathComponent == basename }
    }

    /// Replanning with the SAME title/year must reproduce the original plan
    /// exactly — proves the shared `computeDestination` path didn't drift.
    @Test func replanNoChangeMatchesOriginal() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv"))
        touch(root.appendingPathComponent("Show.S01E01.1080p.mkv"))
        let tv = root.appendingPathComponent("Some.Show.S02.COMPLETE")
        touch(tv.appendingPathComponent("Some.Show.S02E01.mkv"))
        touch(tv.appendingPathComponent("Some.Show.S02E02.mkv"))
        touch(tv.appendingPathComponent("Some.Show.S02E01.eng.srt"))
        let mv = root.appendingPathComponent("Inception.2010.1080p.BluRay")
        touch(mv.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))

        let plan = PlanBuilder.plan(root: root)
        for n in plan.nodes where n.status == .rename {
            let again = PlanBuilder.replan(n, title: n.editTitle, year: n.editYear, root: root)
            #expect(again.previewPairs == n.previewPairs)
            #expect(again.operations == n.operations)
            #expect(again.status == n.status)
        }
    }

    @Test func replanMovieTitleAndYear() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.x264-GROUP.mkv"))
        let plan = PlanBuilder.plan(root: root)
        let n = node(plan.nodes, "Inception.2010.1080p.BluRay.x264-GROUP.mkv")!
        #expect(n.editTitle == "Inception")
        #expect(n.editYear == "2010")

        let edited = PlanBuilder.replan(n, title: "Inception Reborn", year: "2011", root: root)
        #expect(edited.previewPairs.map(\.new)
                == ["Inception Reborn (2011)/Inception Reborn (2011).mkv"])
        #expect(edited.status == .rename)
    }

    @Test func replanTVTitleUpdatesFolderFilenamesAndSidecars() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let tv = root.appendingPathComponent("Some.Show.S02.COMPLETE")
        touch(tv.appendingPathComponent("Some.Show.S02E01.mkv"))
        touch(tv.appendingPathComponent("Some.Show.S02E01.eng.srt"))
        let plan = PlanBuilder.plan(root: root)
        let n = node(plan.nodes, "Some.Show.S02.COMPLETE")!
        #expect(n.editTitle == "Some Show")

        let edited = PlanBuilder.replan(n, title: "Renamed Show", year: "", root: root)
        #expect(Set(edited.previewPairs.map(\.new)) == [
            "Renamed Show/Season 2/Renamed Show S02E01.mkv",
            "Renamed Show/Season 2/Renamed Show S02E01.eng.srt",
        ])
    }

    /// Editing one of two colliding movies to a unique title clears the conflict.
    @Test func replanResolvesConflict() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.x264.mkv"))
        touch(root.appendingPathComponent("Inception.2010.720p.WEB.x264.mkv"))

        var plan = PlanBuilder.plan(root: root)
        #expect(plan.conflicts.count == 2)

        let first = root.appendingPathComponent("Inception.2010.1080p.BluRay.x264.mkv")
        plan = PlanBuilder.replan(plan, itemSource: first, title: "Inception Directors Cut", year: "2010")
        #expect(plan.conflicts.isEmpty)
    }
}
