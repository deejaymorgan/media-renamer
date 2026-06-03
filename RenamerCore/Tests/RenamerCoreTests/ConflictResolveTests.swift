import Testing
import Foundation
@testable import RenamerCore

@Suite("Quality tag parsing")
struct QualityTagTests {

    @Test func parsesResolutionSourceAndDynamicRange() {
        #expect(QualityTag.descriptor("The.Thing.1982.2160p.UHD.BluRay.DV.HDR.x265-REL.mkv")
                == "2160p BluRay DV")
        #expect(QualityTag.descriptor("Inception.2010.1080p.BluRay.x264-AMIABLE.mkv")
                == "1080p BluRay")
        #expect(QualityTag.descriptor("The.Matrix.1999.REMUX.2160p.mkv")
                == "2160p Remux")
    }

    @Test func resolutionLeadsRegardlessOfFilenameOrder() {
        // Source token appears before the resolution token in the filename,
        // but the label still orders resolution first.
        #expect(QualityTag.descriptor("Film.2001.BluRay.1080p.mkv") == "1080p BluRay")
    }

    @Test func appendsEditionAndIsCaseInsensitive() {
        #expect(QualityTag.descriptor("Aliens.1986.Extended.1080p.WEB-DL.DDP5.1.mkv")
                == "1080p WEB-DL Extended")
        #expect(QualityTag.descriptor("show.2020.2160P.web.mkv") == "2160p WEBRip")
    }

    @Test func emptyWhenNoMarkers() {
        #expect(QualityTag.descriptor("Some.Movie.2015.mkv") == "")
    }

    @Test func distinctLabelsBreakTiesAndFillBlanks() {
        let a = URL(fileURLWithPath: "/x/A.1080p.BluRay.mkv")
        let b = URL(fileURLWithPath: "/x/B.1080p.BluRay.mkv")   // identical quality
        let c = URL(fileURLWithPath: "/x/Plain.2010.mkv")       // no markers
        let labels = QualityTag.distinctLabels(for: [a, b, c])
        #expect(labels[a] == "1080p BluRay")
        #expect(labels[b] == "1080p BluRay (2)")
        #expect(labels[c] == "Version")
    }
}

@Suite("Duplicate-target resolution")
struct ConflictResolveTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-resolve-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    /// Two versions of the same movie collide on one destination; labelling them
    /// clears the conflict and yields two distinct files in one shared folder.
    /// (Sharing a title+year, the two loose copies are grouped into one node.)
    @Test func labellingTwoVersionsClearsTheConflict() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let hd = root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv")
        let uhd = root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv")
        touch(hd); touch(uhd)

        let plan = PlanBuilder.plan(root: root)
        #expect(plan.conflicts.count == 2)
        let groups = plan.conflictGroups
        #expect(groups.count == 1)
        #expect(groups.first?.count == 2)
        #expect(plan.conflictGroup(containing: hd) == groups.first)

        let labels = QualityTag.distinctLabels(for: groups[0])
        let resolved = PlanBuilder.resolve(plan, suffixes: labels)
        #expect(resolved.conflicts.isEmpty)

        // The two versions share one node; both resolved names appear in it.
        let node = resolved.nodes.first { $0.mediaType == .movie }
        #expect(node?.status == .rename)
        #expect(Set((node?.previewPairs ?? []).map(\.new)) == [
            "The Thing (1982)/The Thing (1982) - 1080p BluRay.mkv",
            "The Thing (1982)/The Thing (1982) - 2160p BluRay.mkv",
        ])

        // The whole chain executes: both move, nothing skipped.
        let result = Executor.apply(resolved)
        #expect(result.movedCount == 2)
        #expect(result.conflictCount == 0)
        #expect(fm.fileExists(atPath:
            root.appendingPathComponent("The Thing (1982)/The Thing (1982) - 1080p BluRay.mkv").path))
        #expect(fm.fileExists(atPath:
            root.appendingPathComponent("The Thing (1982)/The Thing (1982) - 2160p BluRay.mkv").path))
    }

    /// Clearing labels (the "skip" path) restores the original collision.
    @Test func clearingLabelsRestoresTheConflict() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let hd = root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv")
        let uhd = root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv")
        touch(hd); touch(uhd)

        let plan = PlanBuilder.plan(root: root)
        let resolved = PlanBuilder.resolve(plan, suffixes: QualityTag.distinctLabels(for: plan.conflictGroups[0]))
        #expect(resolved.conflicts.isEmpty)

        let cleared = PlanBuilder.resolve(resolved, suffixes: [hd: "", uhd: ""])
        #expect(cleared.conflicts.count == 2)
    }

    /// A title edit and a version label coexist on the same node.
    @Test func suffixSurvivesAlongsideTitleEdits() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let hd = root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv")
        let uhd = root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv")
        touch(hd); touch(uhd)

        var plan = PlanBuilder.plan(root: root)
        plan = PlanBuilder.resolve(plan, suffixes: QualityTag.distinctLabels(for: plan.conflictGroups[0]))
        // Rename just the 1080p copy's title; the version label must persist.
        plan = PlanBuilder.replan(plan, itemSource: hd, title: "Thing", year: "1982")
        let hdNode = plan.nodes.first { $0.source == hd }
        #expect(hdNode?.previewPairs.first?.new == "Thing (1982)/Thing (1982) - 1080p BluRay.mkv")
    }
}
