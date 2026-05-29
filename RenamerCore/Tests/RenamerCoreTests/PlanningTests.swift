import Testing
import Foundation
@testable import RenamerCore

/// Planning-layer parity tests, mirroring `tests/test_renamer.py`'s
/// plan_input_dir / group_sidecars / detect_dest_conflicts cases.
@Suite("Planning parity with the Python engine")
struct PlanningTests {

    // MARK: - Fixture helpers

    private func makeTempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rc-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private func node(_ plans: [NodePlan], _ basename: String) -> NodePlan? {
        plans.first { $0.source.lastPathComponent == basename }
    }

    // MARK: - End-to-end build

    @Test func endToEndFullPlan() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        touch(root.appendingPathComponent("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv"))
        touch(root.appendingPathComponent("Show.S01E01.1080p.mkv"))
        let tv = root.appendingPathComponent("Some.Show.S02.COMPLETE")
        touch(tv.appendingPathComponent("Some.Show.S02E01.mkv"))
        touch(tv.appendingPathComponent("Some.Show.S02E02.mkv"))
        touch(tv.appendingPathComponent("info.nfo"))
        touch(tv.appendingPathComponent("Sample").appendingPathComponent("sample.mkv"))
        let mv = root.appendingPathComponent("Inception.2010.1080p.BluRay")
        touch(mv.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))
        touch(mv.appendingPathComponent("Inception.2010.eng.srt"))
        let ignored = root.appendingPathComponent("Movies")
        touch(ignored.appendingPathComponent("Some.Other.Movie.2015.1080p.BluRay.mkv"))

        let plans = PlanBuilder.build(root: root)
        #expect(plans.count == 5)

        // Loose movie
        let m = node(plans, "The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv")
        #expect(m?.mediaType == .movie)
        #expect(m?.status == .rename)
        #expect(m?.previewPairs == [PreviewPair(
            old: "The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv",
            new: "The Matrix (1999)/The Matrix (1999).mkv")])

        // Loose TV
        let lt = node(plans, "Show.S01E01.1080p.mkv")
        #expect(lt?.mediaType == .tv)
        #expect(lt?.previewPairs == [PreviewPair(
            old: "Show.S01E01.1080p.mkv",
            new: "Show/Season 1/Show S01E01.mkv")])

        // TV folder
        let tvf = node(plans, "Some.Show.S02.COMPLETE")
        #expect(tvf?.mediaType == .tv)
        #expect(tvf?.status == .rename)
        #expect(Set((tvf?.previewPairs ?? []).map(\.new)) == [
            "Some Show/Season 2/Some Show S02E01.mkv",
            "Some Show/Season 2/Some Show S02E02.mkv",
        ])
        let junkNames = Set((tvf?.junk ?? []).map { $0.lastPathComponent })
        #expect(junkNames.contains("info.nfo"))
        #expect(junkNames.contains("Sample"))

        // Movie folder with sidecar
        let mvf = node(plans, "Inception.2010.1080p.BluRay")
        #expect(mvf?.mediaType == .movie)
        #expect(Set((mvf?.previewPairs ?? []).map(\.new)) == [
            "Inception (2010)/Inception (2010).mkv",
            "Inception (2010)/Inception (2010).eng.srt",
        ])

        // Ignored library folder
        let ig = node(plans, "Movies")
        #expect(ig?.status == .skip)
        #expect(ig?.note.contains("ignored library folder") == true)
    }

    @Test func mixedFolderIsSkipped() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let mixed = root.appendingPathComponent("Mixed.Folder")
        touch(mixed.appendingPathComponent("Show.S01E01.1080p.mkv"))
        touch(mixed.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))

        let p = node(PlanBuilder.build(root: root), "Mixed.Folder")
        #expect(p?.status == .skip)
        #expect(p?.note.lowercased().contains("mixed") == true)
        #expect(p?.note.contains("tv=1") == true)
        #expect(p?.note.contains("movie=1") == true)
    }

    @Test func unparseableFolderNamesOffender() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let f = root.appendingPathComponent("No.Year.Folder")
        touch(f.appendingPathComponent("random.untagged.file.mkv"))

        let p = node(PlanBuilder.build(root: root), "No.Year.Folder")
        #expect(p?.status == .skip)
        #expect(p?.note.contains("random.untagged.file.mkv") == true)
    }

    @Test func alreadyNamedMovieFolderIsUnchanged() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let f = root.appendingPathComponent("Already Named (2020)")
        touch(f.appendingPathComponent("Already Named (2020).mkv"))

        let p = node(PlanBuilder.build(root: root), "Already Named (2020)")
        #expect(p?.status == .unchanged)
    }

    @Test func duplicateTargetsAreConflicts() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.x264.mkv"))
        touch(root.appendingPathComponent("Inception.2010.720p.WEB.x264.mkv"))

        let plan = PlanBuilder.plan(root: root)
        #expect(plan.conflicts.count == 2)
    }

    // MARK: - group sidecars

    @Test func sidecarsSingleVideoCollectsAll() {
        let v = URL(fileURLWithPath: "/x/Movie.mkv")
        let s = [URL(fileURLWithPath: "/x/Movie.eng.srt"),
                 URL(fileURLWithPath: "/x/anything.srt")]
        #expect(Sidecars.group(videos: [v], sidecars: s)[v] == s)
    }

    @Test func sidecarsNone() {
        let a = URL(fileURLWithPath: "/x/A.mkv")
        let b = URL(fileURLWithPath: "/x/B.mkv")
        let out = Sidecars.group(videos: [a, b], sidecars: [])
        #expect(out[a] == [])
        #expect(out[b] == [])
    }

    @Test func sidecarsLongestPrefixMatch() {
        let v1 = URL(fileURLWithPath: "/x/Show.S01E01.mkv")
        let v2 = URL(fileURLWithPath: "/x/Show.S01E02.mkv")
        let s1 = URL(fileURLWithPath: "/x/Show.S01E01.eng.srt")
        let s2 = URL(fileURLWithPath: "/x/Show.S01E02.fre.srt")
        let out = Sidecars.group(videos: [v1, v2], sidecars: [s1, s2])
        #expect(out[v1] == [s1])
        #expect(out[v2] == [s2])
    }

    @Test func sidecarsLanguageStrippedBeforeMatch() {
        let v1 = URL(fileURLWithPath: "/x/Movie.mkv")
        let v2 = URL(fileURLWithPath: "/x/Movie.Extras.mkv")
        let s1 = URL(fileURLWithPath: "/x/Movie.eng.srt")
        let out = Sidecars.group(videos: [v1, v2], sidecars: [s1])
        #expect(out[v1] == [s1])
        #expect(out[v2] == [])
    }

    @Test func sidecarsFallbackToFirstVideo() {
        let a = URL(fileURLWithPath: "/x/Alpha.mkv")
        let b = URL(fileURLWithPath: "/x/Beta.mkv")
        let g = URL(fileURLWithPath: "/x/Gamma.srt")
        let out = Sidecars.group(videos: [a, b], sidecars: [g])
        #expect(out[a] == [g])
        #expect(out[b] == [])
    }

    // MARK: - conflict detection (unit)

    @Test func conflictTwoSourcesSameDest() {
        let dst = URL(fileURLWithPath: "/out/Show/Season 1/Show S01E01.mkv")
        let a = URL(fileURLWithPath: "/in/a.mkv")
        let b = URL(fileURLWithPath: "/in/b.mkv")
        let p1 = NodePlan(source: a, mediaType: .tv, status: .rename,
                          operations: [.move(from: a, to: dst)])
        let p2 = NodePlan(source: b, mediaType: .tv, status: .rename,
                          operations: [.move(from: b, to: dst)])
        let conflicts = ConflictChecker.detect(in: [p1, p2])
        #expect(conflicts.contains(a))
        #expect(conflicts.contains(b))
    }

    @Test func conflictDistinctDestinationsNone() {
        let a = URL(fileURLWithPath: "/in/a.mkv")
        let b = URL(fileURLWithPath: "/in/b.mkv")
        let p1 = NodePlan(source: a, mediaType: .movie, status: .rename,
                          operations: [.move(from: a, to: URL(fileURLWithPath: "/out/A/A.mkv"))])
        let p2 = NodePlan(source: b, mediaType: .movie, status: .rename,
                          operations: [.move(from: b, to: URL(fileURLWithPath: "/out/B/B.mkv"))])
        #expect(ConflictChecker.detect(in: [p1, p2]).isEmpty)
    }
}
