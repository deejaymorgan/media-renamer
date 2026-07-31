import Testing
import Foundation
@testable import RenamerCore

/// Junk is only ever offered for the Trash on a node the app is actually
/// restructuring. A folder it skipped, or one that already has the name it
/// wants, is out of contract — the app is not touching it, so it must not
/// delete anything inside it either.
///
/// These are **Swift-side rules with no Python oracle** (the CLI prompted per
/// folder it was already processing, so it never had this decision to make), the
/// same way the quality-tag and resolver suites are new. This suite is the
/// oracle.
///
/// The regression it pins is a real one: a scan of a downloads folder holding a
/// `seeding/` directory of `.mp4` sports recordings reported "5 junk" and would
/// have trashed 46 GB of actively-seeding files on Apply — while listing none of
/// them, because skipped rows are unselectable and render no junk list.
@Suite("Junk scope (only nodes being renamed)")
struct JunkScopeTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-junkscope-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touch(_ url: URL) {
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    private func node(_ plan: Plan, _ basename: String) -> NodePlan? {
        plan.nodes.first { $0.source.lastPathComponent == basename }
    }

    /// The forensic shape that produced the bug: a folder with no `.mkv`
    /// anywhere, holding nested non-video files and a junk-named subfolder,
    /// beside a loose episode that *does* rename.
    @discardableResult
    private func makeSeedingTree(_ root: URL) -> [URL] {
        let seeding = root.appendingPathComponent("seeding")
        let clips = [
            seeding.appendingPathComponent("afl/1st Preliminary Final.mp4"),
            seeding.appendingPathComponent("afl/Grand Final/1st Quarter.mp4"),
            seeding.appendingPathComponent("afl/Grand Final/2nd Quarter.mp4"),
            seeding.appendingPathComponent("notes.txt"),
        ]
        clips.forEach(touch)
        // A junk-*named* subfolder: the scanner records the whole directory as
        // one junk entry rather than descending, so a single trashItem would
        // take the tree with it.
        touch(seeding.appendingPathComponent("Sample/teaser.mp4"))
        touch(root.appendingPathComponent("Some.Show.S01E01.1080p.mkv"))
        return clips + [seeding.appendingPathComponent("Sample")]
    }

    // MARK: - Skipped folders

    /// The bug, at the model level: the folder is skipped, so it contributes no
    /// junk at all — not through the gate, and not even in the raw scan result,
    /// because `planDirectory` never attaches it on a skip path.
    @Test func skippedFolderWithNoVideosOffersNoJunk() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        makeSeedingTree(root)

        let plan = PlanBuilder.plan(root: root)
        let seeding = node(plan, "seeding")

        #expect(seeding?.status == .skip)
        #expect(seeding?.note.contains("no .mkv files") == true)
        #expect(seeding?.junk.isEmpty == true)
        #expect(seeding?.detectedJunk.isEmpty == true)   // not attached at the source either
    }

    /// The count behind the "N Junk" chip and the Apply trash list is the same
    /// flat-map the app performs, so it must come out empty for a tree whose only
    /// junk lives inside a skipped folder.
    @Test func skippedJunkIsAbsentFromThePlanWideCount() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        makeSeedingTree(root)

        let plan = PlanBuilder.plan(root: root)

        #expect(plan.nodes.flatMap { $0.junk }.isEmpty)
        #expect(plan.nodes.contains { $0.status == .rename })   // there IS a plan; it just has no junk
    }

    /// A folder holding both a movie and an episode is skipped as unrecognised —
    /// same rule, second skip path.
    @Test func mixedContentFolderOffersNoJunk() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Mixed.Bag")
        touch(folder.appendingPathComponent("Some.Show.S01E01.mkv"))
        touch(folder.appendingPathComponent("Inception.2010.mkv"))
        touch(folder.appendingPathComponent("readme.nfo"))

        let plan = PlanBuilder.plan(root: root)
        let mixed = node(plan, "Mixed.Bag")

        #expect(mixed?.status == .skip)
        #expect(mixed?.note.contains("mixed") == true)
        #expect(mixed?.junk.isEmpty == true)
        #expect(mixed?.detectedJunk.isEmpty == true)
    }

    /// A folder whose videos carry no episode code or year is skipped — third
    /// skip path, same rule.
    @Test func unparsableFolderOffersNoJunk() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Holiday.Footage")
        touch(folder.appendingPathComponent("clip one.mkv"))
        touch(folder.appendingPathComponent("cover.jpg"))

        let plan = PlanBuilder.plan(root: root)
        let unparsable = node(plan, "Holiday.Footage")

        #expect(unparsable?.status == .skip)
        #expect(unparsable?.note.contains("no episode code or release year") == true)
        #expect(unparsable?.junk.isEmpty == true)
        #expect(unparsable?.detectedJunk.isEmpty == true)
    }

    // MARK: - Unchanged nodes

    /// An already-correctly-named folder has nothing to do, so it is equally out
    /// of contract. Here the junk *was* detected — the folder parsed fine and was
    /// planned — and the status gate is what withholds it, which is why
    /// `detectedJunk` is deliberately still populated.
    @Test func unchangedNodeWithheldItsJunk() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Inception (2010)")
        touch(folder.appendingPathComponent("Inception (2010).mkv"))
        touch(folder.appendingPathComponent("poster.nfo"))

        let plan = PlanBuilder.plan(root: root)
        let movie = node(plan, "Inception (2010)")

        #expect(movie?.status == .unchanged)
        #expect(movie?.detectedJunk.count == 1)              // the scan found it…
        #expect(movie?.junk.isEmpty == true)                 // …the gate withholds it
        #expect(plan.nodes.flatMap { $0.junk }.isEmpty)
    }

    /// …and it comes straight back when the node has work again. Flipping the
    /// layout gives the already-organised folder somewhere to move to, which
    /// turns it back into a rename node — the reason the raw scan result is kept
    /// rather than discarded at build time.
    @Test func junkReturnsWhenALayoutChangeGivesTheNodeWorkAgain() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Inception (2010)")
        touch(folder.appendingPathComponent("Inception (2010).mkv"))
        touch(folder.appendingPathComponent("poster.nfo"))

        let organised = PlanBuilder.assemble(root: root, cascade: ModeCascade(global: .organise))
        let flat = PlanBuilder.assemble(root: root, cascade: ModeCascade(global: .renameOnly))

        #expect(node(organised, "Inception (2010)")?.status == .unchanged)
        #expect(node(organised, "Inception (2010)")?.junk.isEmpty == true)

        #expect(node(flat, "Inception (2010)")?.status == .rename)
        #expect(node(flat, "Inception (2010)")?.junk.map(\.lastPathComponent) == ["poster.nfo"])
    }

    // MARK: - The renaming case still works

    /// The feature's actual point, guarded against over-reach: junk beside files
    /// that ARE being restructured is still counted, still listed, still trashed.
    @Test func renamingFolderStillOffersItsJunk() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Some.Show.S01.COMPLETE")
        touch(folder.appendingPathComponent("Some.Show.S01E01.mkv"))
        touch(folder.appendingPathComponent("readme.nfo"))
        makeSeedingTree(root)                                 // …alongside a skipped folder

        let plan = PlanBuilder.plan(root: root)
        let show = node(plan, "Some.Show.S01.COMPLETE")

        #expect(show?.status == .rename)
        #expect(show?.junk.map(\.lastPathComponent) == ["readme.nfo"])
        // Exactly one junk file plan-wide: the skipped folder's four contribute
        // nothing, so the chip reads 1 rather than 6.
        #expect(plan.nodes.flatMap { $0.junk }.count == 1)
    }

    // MARK: - End to end

    /// The whole point, on disk: applying a plan whose only junk sits inside a
    /// skipped folder leaves that folder byte-for-byte alone, while the rename it
    /// *was* asked to do still happens.
    @Test func applyLeavesASkippedFoldersContentsAlone() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let untouchable = makeSeedingTree(root)

        let plan = PlanBuilder.plan(root: root)
        // Exactly what AppModel.junkToTrash hands the executor.
        let junk = plan.nodes.flatMap { $0.junk }
        let result = Executor.apply(plan, trashing: junk, using: DeletingTrasher())

        #expect(result.trashedCount == 0)
        #expect(result.movedCount == 1)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Some Show/Season 1/Some Show S01E01.mkv").path))
        for survivor in untouchable {
            #expect(fm.fileExists(atPath: survivor.path), "trashed something inside a skipped folder: \(survivor.lastPathComponent)")
        }
        #expect(fm.fileExists(atPath: root.appendingPathComponent("seeding").path))
    }
}
