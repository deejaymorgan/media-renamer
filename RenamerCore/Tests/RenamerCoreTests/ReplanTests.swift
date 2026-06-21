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

    /// A title edit re-evaluates the empty-source-folder cleanup instead of
    /// freezing the build-time decision (#4). A folder already named after its
    /// title gets no cleanup op at build (it IS the destination); after renaming
    /// the title, the now-orphaned source folder must be scheduled for removal —
    /// and reverting the title drops it again.
    @Test func titleEditReevaluatesEmptySourceCleanup() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Breaking Bad")
        touch(folder.appendingPathComponent("Breaking.Bad.S01E01.mkv"))
        func hasCleanup(_ np: NodePlan) -> Bool {
            np.operations.contains { if case .removeEmptyDirectory = $0 { return true }; return false }
        }

        let n = node(PlanBuilder.plan(root: root).nodes, "Breaking Bad")!
        #expect(!hasCleanup(n))   // source folder already IS the destination

        let edited = PlanBuilder.replan(n, title: "Breaking Bad Remastered", year: "", root: root)
        #expect(edited.operations.contains {
            if case let .removeEmptyDirectory(d) = $0 {
                return d.standardizedFileURL == folder.standardizedFileURL
            }
            return false
        })

        let reverted = PlanBuilder.replan(edited, title: "Breaking Bad", year: "", root: root)
        #expect(!hasCleanup(reverted))   // op isn't frozen — it follows the title
    }

    /// The movie branch of the cleanup re-evaluation: a folder already named
    /// `Title (Year)` schedules no cleanup at build, but editing the year orphans
    /// it (cleanup scheduled), reverting drops it, and clearing the year targets a
    /// bare `Title/` folder — exercising destinationFolder's `Title (Year)`
    /// reconstruction and the cleared-year path. (#4)
    @Test func movieYearEditReevaluatesEmptySourceCleanup() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Inception (2010)")
        touch(folder.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))
        func cleansFolder(_ np: NodePlan) -> Bool {
            np.operations.contains {
                if case let .removeEmptyDirectory(d) = $0 {
                    return d.standardizedFileURL == folder.standardizedFileURL
                }
                return false
            }
        }
        let n = node(PlanBuilder.plan(root: root).nodes, "Inception (2010)")!
        #expect(!cleansFolder(n))   // folder already IS the destination

        let bumped = PlanBuilder.replan(n, title: "Inception", year: "2011", root: root)
        #expect(bumped.previewPairs.map(\.new) == ["Inception (2011)/Inception (2011).mkv"])
        #expect(cleansFolder(bumped))

        #expect(!cleansFolder(PlanBuilder.replan(bumped, title: "Inception", year: "2010", root: root)))
        let cleared = PlanBuilder.replan(bumped, title: "Inception", year: "", root: root)
        #expect(cleared.previewPairs.map(\.new) == ["Inception/Inception.mkv"])
        #expect(cleansFolder(cleared))
    }

    /// Editing one of two colliding movie *folders* to a unique title clears the
    /// conflict. (Two loose copies of one title now share a single node, so a
    /// per-node title edit can't split them — that's the version-label resolver's
    /// job; see ConflictResolveTests. Separate folders stay separate nodes.)
    @Test func replanResolvesConflict() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let hd = root.appendingPathComponent("Inception.2010.1080p.BluRay.x264")
        let sd = root.appendingPathComponent("Inception.2010.720p.WEB.x264")
        touch(hd.appendingPathComponent("Inception.2010.1080p.BluRay.x264.mkv"))
        touch(sd.appendingPathComponent("Inception.2010.720p.WEB.x264.mkv"))

        var plan = PlanBuilder.plan(root: root)
        #expect(plan.conflicts.count == 2)

        // Use the node's own source URL — a directory listing can add a trailing
        // slash that a hand-built URL lacks (the app always passes node.source).
        let hdNode = node(plan.nodes, "Inception.2010.1080p.BluRay.x264")!
        plan = PlanBuilder.replan(plan, itemSource: hdNode.source,
                                  title: "Inception Directors Cut", year: "2010")
        #expect(plan.conflicts.isEmpty)
    }
}
