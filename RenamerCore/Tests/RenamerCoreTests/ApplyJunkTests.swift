import Testing
import Foundation
@testable import RenamerCore

/// A Trasher test double that *permanently deletes* (no real Trash involved), so
/// the trash-then-move-then-cleanup orchestration can be verified end to end
/// without polluting the developer's actual Trash.
struct DeletingTrasher: Trasher {
    func trash(_ urls: [URL]) -> [TrashOutcome] {
        urls.map { url in
            try? FileManager.default.removeItem(at: url)
            return TrashOutcome(source: url, trashedTo: nil, error: nil)
        }
    }
}

@Suite("Apply with junk trashing")
struct ApplyJunkTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-applyjunk-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    @Test func trashesJunkThenMovesAndRemovesEmptiedSource() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Some.Show.S01.COMPLETE")
        touch(folder.appendingPathComponent("Some.Show.S01E01.mkv"))
        touch(folder.appendingPathComponent("Some.Show.S01E02.mkv"))
        touch(folder.appendingPathComponent("info.nfo"))   // junk

        let plan = PlanBuilder.plan(root: root)
        let junk = plan.nodes.flatMap { $0.junk }
        #expect(junk.count == 1)

        let result = Executor.apply(plan, trashing: junk, using: DeletingTrasher())
        #expect(result.trashedCount == 1)
        #expect(result.movedCount == 2)
        #expect(result.errorCount == 0)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Some Show/Season 1/Some Show S01E01.mkv").path))
        // junk gone + episodes moved out ⇒ source folder is empty ⇒ removed
        #expect(!fm.fileExists(atPath: folder.path))
    }

    @Test func keptJunkLeavesSourceFolder() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Some.Show.S01.COMPLETE")
        touch(folder.appendingPathComponent("Some.Show.S01E01.mkv"))
        touch(folder.appendingPathComponent("info.nfo"))   // junk, but kept

        let plan = PlanBuilder.plan(root: root)
        // Trash nothing (user unchecked the junk) → folder retains it.
        let result = Executor.apply(plan, trashing: [], using: DeletingTrasher())
        #expect(result.trashedCount == 0)
        #expect(result.movedCount == 1)
        #expect(fm.fileExists(atPath: folder.path))
        #expect(fm.fileExists(atPath: folder.appendingPathComponent("info.nfo").path))
    }
}
