import Testing
import Foundation
@testable import RenamerCore

@Suite("Version-tail parsing")
struct VersionTailTests {

    @Test func parsesOurOwnTail() {
        let m = MediaParser.movie("The Thing (1982) - 2160p BluRay.mkv")
        #expect(m?.title == "The Thing (1982)")
        #expect(m?.versionLabel == "2160p BluRay")

        let tv = MediaParser.tv("Severance S01E01 - 1080p WEB-DL.mkv")
        #expect(tv?.episodeCode == "S01E01")
        #expect(tv?.versionLabel == "1080p WEB-DL")
    }

    @Test func ignoresSceneTailsAndNonCanonicalYears() {
        // Scene metadata sits after a '.', not a ' - ' → not our tail.
        #expect(MediaParser.movie("The.Thing.1982.2160p.UHD.BluRay.mkv")?.versionLabel == "")
        #expect(MediaParser.tv("Severance.S01E01.1080p.WEB-DL.mkv")?.versionLabel == "")
        // A release-group hyphen (no surrounding spaces) is not our tail.
        #expect(MediaParser.tv("Severance S01E01-GROUP.mkv")?.versionLabel == "")
        // Plain canonical name, no tail.
        #expect(MediaParser.movie("Inception (2010).mkv")?.versionLabel == "")
    }

    @Test func tailDoesNotDisturbTheTitle() {
        // A ' - ' inside the title (before the year) is untouched; only the tail
        // after a canonical year is captured.
        let m = MediaParser.movie("Mission - Impossible (1996) - 1080p.mkv")
        #expect(m?.title == "Mission - Impossible (1996)")
        #expect(m?.versionLabel == "1080p")
    }
}

@Suite("Apply is idempotent")
struct IdempotencyTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-idem-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    /// Resolve two versions, apply, then re-scan: the tree must be conflict-free
    /// and require no further work — and applying again moves nothing.
    @Test func reScanningResolvedVersionsIsStable() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("The.Thing.1982.1080p.BluRay.mkv"))
        touch(root.appendingPathComponent("The.Thing.1982.2160p.UHD.BluRay.mkv"))

        var plan = PlanBuilder.plan(root: root)
        plan = PlanBuilder.resolve(plan, suffixes: QualityTag.distinctLabels(for: plan.conflictGroups[0]))
        #expect(Executor.apply(plan).movedCount == 2)

        // Re-scan the now-renamed tree.
        let rescan = PlanBuilder.plan(root: root)
        #expect(rescan.conflicts.isEmpty)
        #expect(rescan.nodes.allSatisfy { $0.status != .rename })   // nothing left to do

        // Applying again is a complete no-op.
        let again = Executor.apply(rescan)
        #expect(again.movedCount == 0)
        #expect(again.conflictCount == 0)
        #expect(fm.fileExists(atPath:
            root.appendingPathComponent("The Thing (1982)/The Thing (1982) - 1080p BluRay.mkv").path))
        #expect(fm.fileExists(atPath:
            root.appendingPathComponent("The Thing (1982)/The Thing (1982) - 2160p BluRay.mkv").path))
    }

    /// A subtitle sidecar inherits its video's version label, so a resolved pair
    /// with sidecars is also stable on re-scan.
    @Test func resolvedSidecarsAreStable() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("The Thing (1982)")
        touch(folder.appendingPathComponent("The Thing (1982) - 1080p BluRay.mkv"))
        touch(folder.appendingPathComponent("The Thing (1982) - 1080p BluRay.eng.srt"))
        touch(folder.appendingPathComponent("The Thing (1982) - 2160p Remux.mkv"))
        touch(folder.appendingPathComponent("The Thing (1982) - 2160p Remux.eng.srt"))

        let plan = PlanBuilder.plan(root: root)
        #expect(plan.conflicts.isEmpty)
        #expect(plan.nodes.allSatisfy { $0.status != .rename })
    }
}
