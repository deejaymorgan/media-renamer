import Testing
import Foundation
@testable import RenamerCore

@Suite("All-caps word collection (acronyms)")
struct AcronymTests {

    @Test func collectsAllCapsFromTitlePortions() {
        let words = MediaParser.collectAllCapsWords([
            "FBI.S01E01.pilot.720p.WEB-DL.mkv",
            "WALL-E.2008.1080p.BluRay.x264-GROUP.mkv",
            "Breaking.Bad.S01E01.1080p.mkv",
        ])
        #expect(words == ["FBI", "WALL"])
    }

    @Test func ignoresSingleLetterAndNonCaps() {
        // "E" (1 letter) and ordinary words are excluded.
        #expect(MediaParser.collectAllCapsWords(["The.Show.S01E01.mkv"]) == [])
    }

    @Test func dropsLeftOfAKAForMovies() {
        let words = MediaParser.collectAllCapsWords([
            "Lat.den.AKA.The.NASA.Story.2008.DVDRip.x264-GROUP.mkv"
        ])
        #expect(words == ["NASA"])
    }

    @Test func nonMediaFilenameYieldsNothing() {
        #expect(MediaParser.collectAllCapsWords(["random.untagged.file.mkv"]) == [])
    }

    /// End-to-end: a default "keep ≤4 chars" acronym map preserves FBI / WALL
    /// through the full plan.
    @Test func defaultAcronymMapKeepsShortAcronyms() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rc-acro-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        fm.createFile(atPath: root.appendingPathComponent("FBI.S04E01.hero.720p.WEB-DL.mkv").path,
                      contents: Data())
        fm.createFile(atPath: root.appendingPathComponent("WALL-E.2008.1080p.BluRay.x264-GROUP.mkv").path,
                      contents: Data())

        let words = PlanBuilder.allCapsWords(root: root)
        #expect(words == ["FBI", "WALL"])

        var map: [String: String] = [:]
        for w in words where w.count <= 4 { map[w] = w }   // keep short acronyms
        let plan = PlanBuilder.plan(root: root, acronyms: map)
        let news = Set(plan.nodes.flatMap { $0.previewPairs.map(\.new) })
        #expect(news.contains("FBI/Season 4/FBI S04E01.mkv"))
        #expect(news.contains("WALL-E (2008)/WALL-E (2008).mkv"))
    }
}
