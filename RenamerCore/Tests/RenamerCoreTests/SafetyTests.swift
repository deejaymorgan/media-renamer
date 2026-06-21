import Testing
import Foundation
@testable import RenamerCore

/// Pre-release safety nets: edited titles/years can never escape the chosen
/// root or split a name across directories, and symlinked folders are not
/// followed (no loops, no off-tree relocation on Apply).
@Suite("Destination & scan safety")
struct SafetyTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-safety-\(UUID().uuidString)")
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

    /// A `/` typed into the title field must collapse to a single path
    /// component, not spawn a nested directory.
    @Test func editedTitleSlashStaysOneComponent() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Show.S01E01.mkv"))
        let plan = PlanBuilder.plan(root: root)
        let n = node(plan.nodes, "Show.S01E01.mkv")!

        let edited = PlanBuilder.replan(n, title: "AC/DC Live", year: "", root: root)
        #expect(edited.previewPairs.map(\.new) == ["AC-DC Live/Season 1/AC-DC Live S01E01.mkv"])
    }

    /// A traversal attempt in the title must never resolve above the root.
    @Test func editedTitleTraversalStaysUnderRoot() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Show.S01E01.mkv"))
        let plan = PlanBuilder.plan(root: root)
        let n = node(plan.nodes, "Show.S01E01.mkv")!

        let edited = PlanBuilder.replan(n, title: "../../Escape", year: "", root: root)
        // Slashes are flattened to a single, harmless leading component, so the
        // standardized destination still resolves underneath the root.
        let dest = root.appendingPathComponent(edited.previewPairs[0].new).standardizedFileURL
        #expect(dest.path.hasPrefix(root.standardizedFileURL.path + "/"))
        #expect(edited.previewPairs[0].new == "..-..-Escape/Season 1/..-..-Escape S01E01.mkv")
    }

    /// A bare `..` (no separators to flatten) falls back rather than walking up.
    @Test func dotOnlyTitleFallsBackToUntitled() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Show.S01E01.mkv"))
        let plan = PlanBuilder.plan(root: root)
        let n = node(plan.nodes, "Show.S01E01.mkv")!

        let edited = PlanBuilder.replan(n, title: "..", year: "", root: root)
        #expect(edited.previewPairs.map(\.new) == ["Untitled/Season 1/Untitled S01E01.mkv"])
    }

    /// An empty title can't produce a nameless folder.
    @Test func emptyTitleFallsBackToUntitled() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))
        let plan = PlanBuilder.plan(root: root)
        let n = node(plan.nodes, "Inception.2010.1080p.BluRay.mkv")!

        let edited = PlanBuilder.replan(n, title: "", year: "2010", root: root)
        #expect(edited.previewPairs.map(\.new) == ["Untitled (2010)/Untitled (2010).mkv"])
    }

    /// Clearing a movie's year drops the empty `()` instead of `Title ()`.
    @Test func emptyMovieYearDropsParenthetical() {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))
        let plan = PlanBuilder.plan(root: root)
        let n = node(plan.nodes, "Inception.2010.1080p.BluRay.mkv")!

        let edited = PlanBuilder.replan(n, title: "Inception", year: "", root: root)
        #expect(edited.previewPairs.map(\.new) == ["Inception/Inception.mkv"])
    }

    /// PlanBuilder.build must not follow a symlinked directory sitting at the
    /// root: its out-of-tree media must not be planned for relocation, and Apply
    /// must leave the link's target untouched. (Scanner.walk already guards
    /// nested symlinks; the root listing was the gap.)
    @Test func buildSkipsRootLevelSymlink() throws {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        // An out-of-tree directory holding real media the user did NOT choose.
        let outside = makeTempRoot(); defer { try? fm.removeItem(at: outside) }
        let stranger = outside.appendingPathComponent("Other.S09E09.1080p.mkv")
        touch(stranger)
        // A symlink at the root pointing into it.
        try fm.createSymbolicLink(at: root.appendingPathComponent("linked"),
                                  withDestinationURL: outside)
        // A normal loose movie so the plan isn't empty.
        touch(root.appendingPathComponent("Inception.2010.1080p.BluRay.mkv"))

        let plan = PlanBuilder.plan(root: root)

        // The symlink becomes an inert skip node with no operations.
        let link = node(plan.nodes, "linked")
        #expect(link?.status == .skip)
        #expect(link?.operations.isEmpty == true)
        // Nothing from inside the link is scheduled to move.
        let touchesLink = plan.nodes.flatMap(\.operations).contains { op in
            if case let .move(from, _) = op { return from.path.contains("/linked/") }
            return false
        }
        #expect(!touchesLink)

        _ = Executor.apply(plan)
        #expect(fm.fileExists(atPath: stranger.path))                          // target media untouched
        #expect(Scanner.isSymlink(root.appendingPathComponent("linked")))      // link itself not removed
    }

    /// The root-level symlink guard fires for FILE and BROKEN symlinks too, not
    /// just directory symlinks — it keys on isSymlink (checked before isDirectory),
    /// so a regression narrowing it to "isSymlink && isDirectory" would re-expose
    /// a file-symlink-to-.mkv to relocation. Locks the guard's full reach.
    @Test func buildSkipsRootLevelFileAndBrokenSymlinks() throws {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let outside = makeTempRoot(); defer { try? fm.removeItem(at: outside) }
        let realMkv = outside.appendingPathComponent("Stranger.S01E01.1080p.mkv")
        touch(realMkv)
        // (a) a file symlink with a parseable .mkv name → an out-of-tree real file.
        try fm.createSymbolicLink(at: root.appendingPathComponent("Linked.S02E02.1080p.mkv"),
                                  withDestinationURL: realMkv)
        // (b) a broken symlink with a parseable .mkv name.
        try fm.createSymbolicLink(at: root.appendingPathComponent("Broken.S03E03.1080p.mkv"),
                                  withDestinationURL: outside.appendingPathComponent("nope.mkv"))

        let plan = PlanBuilder.plan(root: root)
        for name in ["Linked.S02E02.1080p.mkv", "Broken.S03E03.1080p.mkv"] {
            #expect(node(plan.nodes, name)?.status == .skip)
            #expect(node(plan.nodes, name)?.operations.isEmpty == true)
        }
        _ = Executor.apply(plan)
        #expect(fm.fileExists(atPath: realMkv.path))   // out-of-tree target untouched
    }

    /// scanContents must not follow symlinked directories: a self-referential
    /// link can't loop, and an out-of-tree link's contents aren't pulled in.
    @Test func scanContentsSkipsSymlinkedDirectories() throws {
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Show.S01")
        touch(folder.appendingPathComponent("Show.S01E01.mkv"))

        // A self-referential link would loop forever if descended into.
        try fm.createSymbolicLink(at: folder.appendingPathComponent("loop"),
                                  withDestinationURL: folder)
        // A link to an out-of-tree folder whose media must NOT be collected.
        let outside = root.appendingPathComponent("outside")
        touch(outside.appendingPathComponent("Other.S09E09.mkv"))
        try fm.createSymbolicLink(at: folder.appendingPathComponent("link"),
                                  withDestinationURL: outside)

        let (videos, _, junk) = Scanner.scanContents(folder)
        #expect(videos.map { $0.lastPathComponent } == ["Show.S01E01.mkv"])
        // The symlinks themselves are skipped, not offered as junk.
        #expect(!junk.contains { $0.lastPathComponent == "loop" || $0.lastPathComponent == "link" })
    }
}
