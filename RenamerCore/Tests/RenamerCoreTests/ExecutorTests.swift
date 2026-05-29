import Testing
import Foundation
@testable import RenamerCore

/// Executor (apply) behaviour, verified against real temp-dir filesystems.
@Suite("Executor (apply) behaviour")
struct ExecutorTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-exec-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    private func exists(_ root: URL, _ relative: String) -> Bool {
        fm.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    @Test func appliesTVFolderAndRemovesEmptiedSource() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Some.Show.S02.COMPLETE")
        touch(folder.appendingPathComponent("Some.Show.S02E01.mkv"))
        touch(folder.appendingPathComponent("Some.Show.S02E02.mkv"))

        let result = Executor.apply(PlanBuilder.plan(root: root))

        #expect(result.movedCount == 2)
        #expect(result.conflictCount == 0)
        #expect(result.errorCount == 0)
        #expect(exists(root, "Some Show/Season 2/Some Show S02E01.mkv"))
        #expect(exists(root, "Some Show/Season 2/Some Show S02E02.mkv"))
        #expect(!fm.fileExists(atPath: folder.path))   // emptied source removed
    }

    @Test func keepsSourceFolderWhenJunkRemains() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Some.Show.S01.COMPLETE")
        touch(folder.appendingPathComponent("Some.Show.S01E01.mkv"))
        touch(folder.appendingPathComponent("readme.nfo"))   // junk, not moved

        let result = Executor.apply(PlanBuilder.plan(root: root))

        #expect(result.movedCount == 1)
        #expect(exists(root, "Some Show/Season 1/Some Show S01E01.mkv"))
        #expect(fm.fileExists(atPath: folder.path))          // junk remains → folder kept
        #expect(fm.fileExists(atPath: folder.appendingPathComponent("readme.nfo").path))
    }

    @Test func appliesLooseMovie() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv"))

        let result = Executor.apply(PlanBuilder.plan(root: root))

        #expect(result.movedCount == 1)
        #expect(result.completedMoves.count == 1)
        #expect(exists(root, "The Matrix (1999)/The Matrix (1999).mkv"))
    }

    @Test func skipsExistingDestination() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.x264.mkv"))
        // Pre-create the destination (this also makes an already-named, unchanged
        // "Inception (2010)" folder node, which the executor ignores).
        touch(root.appendingPathComponent("Inception (2010)/Inception (2010).mkv"))

        let result = Executor.apply(PlanBuilder.plan(root: root))

        #expect(result.movedCount == 0)
        #expect(result.conflictCount == 1)
        #expect(exists(root, "Inception.2010.1080p.BluRay.x264.mkv"))   // source untouched
    }

    @Test func skipsBatchConflicts() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.x264.mkv"))
        touch(root.appendingPathComponent("Inception.2010.720p.WEB.x264.mkv"))

        let plan = PlanBuilder.plan(root: root)
        #expect(plan.conflicts.count == 2)

        let result = Executor.apply(plan)
        #expect(result.movedCount == 0)
        #expect(result.conflictCount == 2)
        #expect(exists(root, "Inception.2010.1080p.BluRay.x264.mkv"))   // both untouched
        #expect(exists(root, "Inception.2010.720p.WEB.x264.mkv"))
    }

    @Test func systemTrasherTrashesAndReports() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let junk = root.appendingPathComponent("delete-me.nfo")
        touch(junk)

        let outcomes = SystemTrasher().trash([junk])

        #expect(outcomes.count == 1)
        #expect(outcomes[0].error == nil)
        #expect(!fm.fileExists(atPath: junk.path))
        // Leave no residue in the real Trash.
        if let trashed = outcomes[0].trashedTo { try? fm.removeItem(at: trashed) }
    }
}
