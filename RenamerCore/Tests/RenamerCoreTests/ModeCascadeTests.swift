import Testing
import Foundation
@testable import RenamerCore

/// `ModeCascade.mode(for:mediaType:)` is the single place the three-level
/// output-mode setting (item → group → global) is collapsed into one decision,
/// and every destination the engine computes hangs off its answer. These tests
/// exercise the resolution rule ALONE — no filesystem, no `PlanBuilder` — so a
/// break here points at the rule itself rather than at planning or naming.
@Suite("Mode cascade (item → group → global)")
struct ModeCascadeTests {

    /// Nothing here touches disk; these paths only need to be distinct URLs.
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private var show: URL { url("/library/Some.Show.S01E01.mkv") }
    private var movie: URL { url("/library/Some.Movie.2010.1080p.BluRay.mkv") }

    /// `MediaType` is not `CaseIterable`; keep the roster in one place so a test
    /// that means "every kind of node" really covers every kind.
    private var allMediaTypes: [MediaType] { [.tv, .movie, .unknown] }

    /// The headline rule: the NEAREST explicit setting wins. Each row pins one
    /// rung of the ladder, and each appears in both directions so neither mode is
    /// privileged — a resolver that hard-coded "rename-only always wins" (an easy
    /// mistake, since rename-only is the product default the UI ships) would pass
    /// half the rows and fail the other half.
    @Test func nearestExplicitLevelWinsInBothDirections() {
        let rows: [(global: OutputMode, group: ModeOverride, item: ModeOverride, expected: OutputMode)] = [
            // Item beats BOTH the group and the global…
            (.renameOnly, .renameOnly, .organise,   .organise),
            // …and the mirror image.
            (.organise,   .organise,   .renameOnly, .renameOnly),
            // With the item deferring, the group beats the global — both ways.
            (.renameOnly, .organise,   .inherit,    .organise),
            (.organise,   .renameOnly, .inherit,    .renameOnly),
        ]
        for row in rows {
            let tvCascade = ModeCascade(global: row.global, tv: row.group, items: [show: row.item])
            #expect(tvCascade.mode(for: show, mediaType: .tv) == row.expected)

            // The same ladder governs the movies group.
            let movieCascade = ModeCascade(global: row.global, movies: row.group, items: [movie: row.item])
            #expect(movieCascade.mode(for: movie, mediaType: .movie) == row.expected)
        }
    }

    /// `.inherit` at the item level must defer to the group, and — the part worth
    /// pinning — a STORED `.inherit` has to be indistinguishable from no entry at
    /// all. The UI writes `.inherit` back when the user returns a per-item control
    /// to "follow the group", so if a stored `.inherit` were treated as an
    /// explicit choice the item would freeze at whatever it happened to be and
    /// stop tracking the group toggle. The global is set to the OPPOSITE of the
    /// group, so falling through one rung too far fails here.
    @Test func inheritAtItemDefersToTheGroupAndMatchesAnAbsentEntry() {
        let stored = ModeCascade(global: .organise, tv: .renameOnly, movies: .renameOnly,
                                 items: [show: .inherit, movie: .inherit])
        #expect(stored.mode(for: show, mediaType: .tv) == .renameOnly)
        #expect(stored.mode(for: movie, mediaType: .movie) == .renameOnly)

        let absent = ModeCascade(global: .organise, tv: .renameOnly, movies: .renameOnly)
        #expect(stored.mode(for: show, mediaType: .tv) == absent.mode(for: show, mediaType: .tv))
        #expect(stored.mode(for: movie, mediaType: .movie) == absent.mode(for: movie, mediaType: .movie))
    }

    /// With both the item and its group deferring, the global decides. Driven
    /// over every `OutputMode` so the assertion cannot be satisfied by a resolver
    /// that ignores the global and returns a constant.
    @Test func inheritAtItemAndGroupFallsThroughToTheGlobal() {
        for global in OutputMode.allCases {
            let cascade = ModeCascade(global: global, tv: .inherit, movies: .inherit,
                                      items: [show: .inherit, movie: .inherit])
            #expect(cascade.mode(for: show, mediaType: .tv) == global)
            #expect(cascade.mode(for: movie, mediaType: .movie) == global)
        }
    }

    /// The two group rungs are siblings, not a shared switch: "all TV → rename
    /// only" must leave movies on the global, and vice versa. Someone with a
    /// tidy movie library and a chaotic pile of episodes relies on exactly this
    /// separation, and a single mistyped field in `mode(for:mediaType:)` would
    /// silently flatten one library into the other's shape.
    @Test func groupOverridesDoNotCrossMediaTypes() {
        let tvOnly = ModeCascade(global: .organise, tv: .renameOnly)
        #expect(tvOnly.mode(for: show, mediaType: .tv) == .renameOnly)
        #expect(tvOnly.mode(for: movie, mediaType: .movie) == .organise)

        let moviesOnly = ModeCascade(global: .organise, movies: .renameOnly)
        #expect(moviesOnly.mode(for: movie, mediaType: .movie) == .renameOnly)
        #expect(moviesOnly.mode(for: show, mediaType: .tv) == .organise)
    }

    /// An untouched cascade hands its global to every node, whatever its media
    /// type — and that global defaults to `.organise`. This default is load-
    /// bearing: every pre-existing engine call site (`plan`, `build`, `replan`,
    /// `resolve`, and `assemble` without a cascade) goes through a default-
    /// constructed `ModeCascade`, so `.organise` here is what keeps the original
    /// folder-tree behaviour — and the whole existing parity suite — intact.
    /// Flipping this default would silently re-shape output everywhere.
    @Test func emptyCascadeYieldsItsGlobalEverywhereAndDefaultsToOrganise() {
        let empty = ModeCascade()
        #expect(empty.global == .organise)
        for type in allMediaTypes {
            #expect(empty.mode(for: show, mediaType: type) == .organise)
        }

        // The global genuinely propagates rather than `.organise` being hard-wired.
        let renaming = ModeCascade(global: .renameOnly)
        for type in allMediaTypes {
            #expect(renaming.mode(for: show, mediaType: type) == .renameOnly)
        }
    }

    /// Unparseable media has no group rung — the UI offers "all TV" and "all
    /// Movies" and nothing else — so `.unknown` must skip BOTH group overrides
    /// and land on the global, even when the two groups agree with each other.
    /// (Answering an unknown node with a group's setting would be arbitrary: no
    /// group owns it.) A per-item override, on the other hand, is the escape
    /// hatch that still reaches it, and it must keep working in both directions.
    @Test func unknownMediaSkipsGroupsButHonoursItemOverrides() {
        let stray = url("/library/mystery-recording.mkv")

        let groupsRenaming = ModeCascade(global: .organise, tv: .renameOnly, movies: .renameOnly)
        #expect(groupsRenaming.mode(for: stray, mediaType: .unknown) == .organise)

        let groupsOrganising = ModeCascade(global: .renameOnly, tv: .organise, movies: .organise)
        #expect(groupsOrganising.mode(for: stray, mediaType: .unknown) == .renameOnly)

        // The item rung sits above the media-type switch, so it still applies.
        let pinnedRenaming = ModeCascade(global: .organise, tv: .organise, movies: .organise,
                                         items: [stray: .renameOnly])
        #expect(pinnedRenaming.mode(for: stray, mediaType: .unknown) == .renameOnly)

        let pinnedOrganising = ModeCascade(global: .renameOnly, items: [stray: .organise])
        #expect(pinnedOrganising.mode(for: stray, mediaType: .unknown) == .organise)
    }

    /// `forced` is the ONE place `.inherit` becomes a decision: nil means "defer
    /// upward", and only a concrete case pins a mode. The table is checked to
    /// cover `allCases`, so adding a fourth `ModeOverride` without deciding what
    /// it forces fails here rather than quietly defaulting to a fall-through.
    @Test func forcedMapsInheritToNilAndConcreteCasesToTheirMode() {
        let table: [(override: ModeOverride, forced: OutputMode?)] = [
            (.inherit,    nil),
            (.organise,   .organise),
            (.renameOnly, .renameOnly),
        ]
        for row in table {
            #expect(row.override.forced == row.forced)
        }
        #expect(Set(table.map({ $0.override })) == Set(ModeOverride.allCases))

        // Exactly one case defers upward; every other case must commit to a mode.
        #expect(ModeOverride.allCases.filter({ $0.forced == nil }) == [.inherit])
    }

    /// Item overrides are keyed by the node's source URL, so one must never bleed
    /// onto another node — including a namesake in a different folder, which is
    /// ordinary in a media library ("Season 1/Show.S01E01.mkv" under two shows).
    /// Matching on the basename instead of the full URL would drag an unrelated
    /// node out of its group's mode.
    @Test func itemOverrideDoesNotLeakToOtherNodes() {
        let pinned = url("/library/Show A/Show.S01E01.mkv")
        let namesake = url("/library/Show B/Show.S01E01.mkv")
        let cascade = ModeCascade(global: .organise, items: [pinned: .renameOnly])

        #expect(cascade.mode(for: pinned, mediaType: .tv) == .renameOnly)
        #expect(cascade.mode(for: namesake, mediaType: .tv) == .organise)
        #expect(cascade.mode(for: movie, mediaType: .movie) == .organise)
    }
}
