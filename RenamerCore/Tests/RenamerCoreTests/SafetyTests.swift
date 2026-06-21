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
