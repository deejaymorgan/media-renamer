import Testing
import Foundation
@testable import RenamerCore

/// Create an empty file at `root/<parts…>`, making any missing parents. Lives at
/// file scope rather than inside the suite so the fixture closures below can
/// build a tree without capturing the suite instance. Components are taken
/// variadically so a fixture can spell out `root, "Severance", "Season 1", "…mkv"`
/// without embedding separators in a literal.
private func touch(_ root: URL, _ parts: String...) {
    let url = parts.reduce(root) { $0.appendingPathComponent($1) }
    let fm = FileManager.default
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: url.path, contents: Data())
}

/// The property the whole rename-only design rests on: **flattening creates no
/// new class of name collision.**
///
/// It holds because the destination folder never disambiguates anything the
/// filename does not already carry. For TV the `Season N/` folder is derived
/// from the season number inside the episode code the filename spells out; for
/// movies the folder is *literally* the filename stem. The organised layout is
/// therefore a pure prefix in front of the very name the flat layout uses on its
/// own — so two files that collide when flattened already collided when
/// organised, and vice versa.
///
/// That matters because the two modes share one conflict resolver and one
/// warning surface. If flattening could invent a collision the organised mode
/// never saw, rename-only would silently drop or overwrite files with nothing in
/// the UI to flag it. These tests are the tripwire for that.
@Suite("Mode equivalence (flattening creates no new collisions)")
struct ModeEquivalenceTests {

    private var fm: FileManager { .default }

    private func makeTempRoot() -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("rc-modeeq-\(UUID().uuidString)")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Conflict groups reduced to a comparable shape: a set of sets of paths.
    /// Comparing this rather than a count means a *regrouping* — the same
    /// sources partitioned differently between the modes — cannot hide behind an
    /// equal total, which is exactly the failure a per-file resolver would then
    /// mis-label.
    private func groupShape(_ plan: Plan) -> Set<Set<String>> {
        Set(plan.conflictGroups.map { Set($0.map(\.path)) })
    }

    // MARK: - Fixture table

    /// One input shape, named so a failing assertion points straight at it.
    private struct Fixture {
        let name: String
        /// How many sources collide under `.organise` — the pre-feature
        /// behaviour, and therefore the number the flat side is held to. Pinning
        /// the count rather than merely "some" is what stops the suite passing
        /// if conflict detection breaks on *both* sides at once. `nil` where the
        /// answer legitimately depends on the volume's case sensitivity.
        let expectedConflicts: Int?
        let populate: (URL) -> Void
    }

    private var fixtures: [Fixture] { [

        // The headline case: two rips of one episode in separate scene folders,
        // each carrying its own subtitle. The sidecars must collide exactly as
        // the videos do — four conflicted sources in two groups — because a
        // sidecar that lost its collision when flattened would be silently
        // orphaned on Apply while its video was correctly held back.
        Fixture(name: "duplicate episodes with sidecars, in separate folders",
                expectedConflicts: 4) { root in
            touch(root, "Foundation.S01E01.1080p.WEB-DL", "Foundation.S01E01.1080p.WEB-DL.mkv")
            touch(root, "Foundation.S01E01.1080p.WEB-DL", "Foundation.S01E01.1080p.WEB-DL.eng.srt")
            touch(root, "Foundation.S01E01.2160p.WEB-DL", "Foundation.S01E01.2160p.WEB-DL.mkv")
            touch(root, "Foundation.S01E01.2160p.WEB-DL", "Foundation.S01E01.2160p.WEB-DL.eng.srt")
        },

        // Input that is ALREADY organised. Under `.organise` the file is a
        // resident sitting on its own destination — no move op, so the conflict
        // index keys it by its *source*; under `.renameOnly` the same file
        // becomes a mover, keyed by its *target*. The two modes reach the same
        // verdict by different routes through `ConflictChecker`, which is the
        // likeliest place for the equivalence to quietly break.
        Fixture(name: "already-organised show tree", expectedConflicts: 0) { root in
            touch(root, "Severance", "Season 1", "Severance S01E01.mkv")
        },

        // The everyday upgrade workflow: an organised library plus a freshly
        // downloaded duplicate of an episode it already holds. The stray merges
        // into the show's node, so one node carries both a resident and a mover
        // — and must report the collision in either layout.
        Fixture(name: "organised show plus a stray duplicate episode",
                expectedConflicts: 2) { root in
            touch(root, "Severance", "Season 1", "Severance S01E01.mkv")
            touch(root, "Severance.S01E01.2160p.WEB-DL.mkv")
        },

        // The same shape with the roles swapped by the mode: one copy is already
        // correctly *organised*, the other already correctly *flat*. Whichever
        // mode is chosen, one of the two is the resident and the other the
        // mover. That the answer is the same either way is the strongest
        // evidence the equivalence is structural rather than a coincidence of
        // how these particular fixtures happen to be laid out.
        Fixture(name: "organised episode plus an already-flat-named duplicate",
                expectedConflicts: 2) { root in
            touch(root, "Severance", "Season 1", "Severance S01E01.mkv")
            touch(root, "Severance S01E01.mkv")
        },

        // A multi-episode code. The season folder is derived from `S01`, but the
        // filename keeps the whole `S01E01E02` — nothing about the multi-part
        // span lives in the folder, so it cannot be what separates two rips.
        Fixture(name: "multi-episode code (S01E01E02), two releases",
                expectedConflicts: 2) { root in
            touch(root, "Andor.S01E01E02.1080p.WEB-DL.mkv")
            touch(root, "Andor.S01E01E02.2160p.WEB-DL.mkv")
        },

        // A four-digit (date-style) season. `Season 2024/` is an unusually
        // *specific* folder, which is precisely why it is worth checking: it
        // still adds nothing, because the 2024 came out of the filename.
        Fixture(name: "four-digit season (S2024E01), two releases",
                expectedConflicts: 2) { root in
            touch(root, "Daily.Recap.S2024E01.1080p.WEB.mkv")
            touch(root, "Daily.Recap.S2024E01.2160p.WEB.mkv")
        },

        // Titles that differ only in the case of a mid-title stopword ("For" vs
        // "for"). On a case-insensitive volume — the macOS default — the folders
        // collide and so do the flat names; on a case-sensitive one neither
        // does. Either way the two modes must agree, which is why this fixture
        // asserts the equivalence but not a fixed conflict count.
        Fixture(name: "two titles differing only in case",
                expectedConflicts: nil) { root in
            touch(root, "Wicked.For.Good.2024.1080p.BluRay.mkv")
            touch(root, "wicked.for.good.2024.2160p.bluray.mkv")
        },

        // Two versions of one movie. Here the organised folder is literally the
        // flat filename's stem, so the claim "the folder disambiguates nothing"
        // is at its most naked.
        Fixture(name: "two versions of one movie (1080p vs 2160p)",
                expectedConflicts: 2) { root in
            touch(root, "The.Thing.1982.1080p.BluRay.mkv")
            touch(root, "The.Thing.1982.2160p.UHD.BluRay.mkv")
        },

        // A clean shape, and deliberately the one a sceptic would expect
        // flattening to break: two season folders and a movie folder all
        // collapsing into a single root. Nothing collides, because every name
        // still carries its own episode code or year. The non-empty fixtures
        // above are what give this suite its teeth — this one is here so a
        // no-collision input is covered too, and it is the reason at least one
        // fixture must assert a NON-zero count.
        Fixture(name: "nothing collides: two seasons and a movie",
                expectedConflicts: 0) { root in
            touch(root, "Severance", "Season 1", "Severance S01E01.mkv")
            touch(root, "Severance", "Season 2", "Severance S02E01.mkv")
            touch(root, "Inception (2010)", "Inception (2010).mkv")
        },
    ] }

    // MARK: - Tests

    /// The contract, over the whole fixture table: for one input folder the set
    /// of conflicted sources — and the way those sources are partitioned into
    /// groups — is identical under `.organise` and `.renameOnly`.
    ///
    /// The two layout assertions are not decoration. Without them the whole
    /// comparison would still pass if `.renameOnly` were ignored outright (both
    /// sides would simply be the organised plan), so they prove the two plans
    /// really are different shapes before their conflicts are compared. A
    /// destination name can never contain "/" — `sanitizeSeparators` strips it
    /// from every user-editable piece — so "no slash in the root-relative path"
    /// is exactly "sits directly in the root".
    @Test func conflictSetsAreIdenticalUnderBothModes() {
        for fixture in fixtures {
            let root = makeTempRoot()
            defer { try? fm.removeItem(at: root) }
            fixture.populate(root)

            // `.organise` is the pre-feature layout — nodes are built in it and
            // `applyModes` leaves them untouched — so this really is old-vs-new.
            let tree = PlanBuilder.assemble(root: root, cascade: ModeCascade(global: .organise))
            let flat = PlanBuilder.assemble(root: root, cascade: ModeCascade(global: .renameOnly))

            let treeNew = tree.nodes.flatMap { $0.previewPairs.map(\.new) }
            let flatNew = flat.nodes.flatMap { $0.previewPairs.map(\.new) }
            #expect(!flatNew.isEmpty,
                    "\(fixture.name): fixture produced no destinations at all")
            #expect(flatNew.allSatisfy({ !$0.contains("/") }),
                    "\(fixture.name): rename-only still built a folder tree — \(flatNew)")
            #expect(treeNew.contains(where: { $0.contains("/") }),
                    "\(fixture.name): organise built no folder tree, so there is nothing to flatten")

            #expect(Set(tree.conflicts.map(\.path)) == Set(flat.conflicts.map(\.path)),
                    "\(fixture.name): flattening changed WHICH sources conflict")
            #expect(groupShape(tree) == groupShape(flat),
                    "\(fixture.name): flattening regrouped the conflicts")

            if let expected = fixture.expectedConflicts {
                #expect(tree.conflicts.count == expected,
                        "\(fixture.name): expected \(expected) conflicted sources under .organise, got \(tree.conflicts.count)")
            }
        }
    }

    /// The mechanism itself, shown on a single colliding pair rather than
    /// inferred from plans: two sources whose names already match land on ONE
    /// destination in *either* mode. Organise prepends `Show/Season N/` — a
    /// prefix computed from the same title and the season inside the very
    /// episode code the name carries — so it can only push the collision deeper,
    /// never split it. For movies the prefix is the filename stem verbatim.
    ///
    /// The literal expectations matter: without them "both flat destinations are
    /// equal" would also be satisfied by a mode that produced nothing at all,
    /// and the point that the two modes differ in *depth* would go unpinned.
    @Test func collidingPairSharesOneDestinationAtEitherDepth() {
        // Purely lexical — `computeDestination` never touches disk, so a
        // synthetic root keeps the mechanism visible with no fixture noise.
        let root = URL(fileURLWithPath: "/library")

        func dest(_ unit: RenameUnit, _ mode: OutputMode,
                  title: String, year: String = "") -> String {
            PlanBuilder.relativePath(
                PlanBuilder.computeDestination(unit, title: title, year: year,
                                               root: root, mode: mode),
                from: root)
        }

        // Two rips of one episode, sitting in different source folders.
        let hd = RenameUnit(source: root.appendingPathComponent("a/Foundation.S01E01.1080p.mkv"),
                            episodeCode: "S01E01", season: 1, languageSuffix: "", ext: ".mkv")
        let uhd = RenameUnit(source: root.appendingPathComponent("b/Foundation.S01E01.2160p.mkv"),
                             episodeCode: "S01E01", season: 1, languageSuffix: "", ext: ".mkv")

        #expect(dest(hd, .renameOnly, title: "Foundation") == "Foundation S01E01.mkv")
        #expect(dest(uhd, .renameOnly, title: "Foundation") == "Foundation S01E01.mkv")
        #expect(dest(hd, .organise, title: "Foundation")
                == "Foundation/Season 1/Foundation S01E01.mkv")
        #expect(dest(uhd, .organise, title: "Foundation")
                == "Foundation/Season 1/Foundation S01E01.mkv")

        // Same collision, different depth: the flat destination is exactly the
        // leaf of the organised one, so the folders are a pure prefix carrying
        // no information the filename lacks.
        #expect(dest(hd, .organise, title: "Foundation")
                .hasSuffix("/" + dest(hd, .renameOnly, title: "Foundation")))

        // Movies make the derivation explicit: the folder IS the filename stem,
        // so it cannot possibly separate two files whose names already match.
        let bluRay = RenameUnit(source: root.appendingPathComponent("The.Thing.1982.1080p.mkv"),
                                episodeCode: nil, season: nil, languageSuffix: "", ext: ".mkv")
        let remux = RenameUnit(source: root.appendingPathComponent("The.Thing.1982.2160p.mkv"),
                               episodeCode: nil, season: nil, languageSuffix: "", ext: ".mkv")

        #expect(dest(bluRay, .renameOnly, title: "The Thing", year: "1982")
                == "The Thing (1982).mkv")
        #expect(dest(remux, .renameOnly, title: "The Thing", year: "1982")
                == "The Thing (1982).mkv")
        #expect(dest(bluRay, .organise, title: "The Thing", year: "1982")
                == "The Thing (1982)/The Thing (1982).mkv")
        #expect(dest(remux, .organise, title: "The Thing", year: "1982")
                == "The Thing (1982)/The Thing (1982).mkv")
    }
}
