import SwiftUI
import RenamerCore

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            if let plan = model.plan {
                let g = PlanGroups(plan)

                AllItemsRow(count: g.tvRename.count + g.movieRename.count,
                            selected: model.selection == .all)
                    .tag(Selection.all)

                // The section also renders when the group is EMPTY but carries an
                // explicit override — its header holds the only control that can
                // clear it, and overrides outlive an Apply. Without this, applying
                // a plan (which leaves every renamed node `.unchanged`) would hide
                // a pinned override while it stayed in force.
                if !g.tvRename.isEmpty || model.tvOverride != .inherit {
                    Section {
                        ForEach(g.tvRename) { show in
                            ShowRow(node: show, conflicts: plan.conflicts,
                                    model: model,
                                    expanded: model.isShowExpanded(show.source),
                                    canExpand: show.isMultiSeason,
                                    onTap: {
                                        model.selection = .item(show.source)
                                        if show.isMultiSeason { model.toggleShow(show.source) }
                                    })
                                .tag(Selection.item(show.source))

                            if show.isMultiSeason, model.isShowExpanded(show.source) {
                                ForEach(show.seasonSlices) { slice in
                                    SeasonRow(slice: slice, show: show,
                                              conflicts: plan.conflicts, model: model)
                                        .tag(Selection.season(show: show.source, number: slice.number))
                                }
                            }
                        }
                    } header: {
                        GroupModeHeader(title: "TV", type: .tv, model: model)
                    }
                }
                if !g.movieRename.isEmpty || model.movieOverride != .inherit {
                    Section {
                        ForEach(g.movieRename) { node in
                            SidebarRow(node: node, conflicts: plan.conflicts, model: model)
                                .tag(Selection.item(node.source))
                        }
                    } header: {
                        GroupModeHeader(title: "Movies", type: .movie, model: model)
                    }
                }
                if !g.unchanged.isEmpty {
                    Section("Unchanged") {
                        ForEach(g.unchanged) { node in
                            // A node pinned here BY an explicit layout override
                            // stays selectable, so the setting that put it here can
                            // be undone in place — the same reason the group
                            // sections above survive an empty bucket.
                            if model.hasSelectableRow(node) {
                                PinnedRow(node: node, conflicts: plan.conflicts, model: model)
                                    .tag(Selection.item(node.source))
                            } else {
                                MutedRow(name: node.originalName, detail: "already named")
                            }
                        }
                    }
                }
                if !g.skipped.isEmpty {
                    Section("Skipped") {
                        ForEach(g.skipped) { node in
                            MutedRow(name: node.originalName, detail: node.note)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.hasMultiSeasonShow {
                HStack(spacing: 12) {
                    Button("Expand all") { model.expandAllShows() }
                    Button("Collapse all") { model.collapseAllShows() }
                    Spacer()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
    }
}

/// A hover wash for every sidebar row that responds to a click.
///
/// The whole list used to sit dead under the pointer, which was survivable while
/// each row carried a chip that lit up on its own. It is not survivable now that
/// the layout setting has moved to a right-click: a list that never reacts reads
/// as text, and text does not invite a right-click.
///
/// Applied to everything **selectable** — "All items" and the show/movie/season/
/// pinned rows. Only `MutedRow` stays dark, because it is genuinely inert: not
/// selectable, no menu, nothing to click. So the wash means "this row does
/// something", which is the property that makes it worth drawing.
///
/// Suppressed while the row is selected: the selection highlight already owns
/// the row, and stacking a wash on top of it only muddies the colour.
///
/// Drawn as a **row background**, not a background on the row's content. The
/// content is inset from the row, so a wash on it lands narrower than the
/// selection capsule and the two read as different shapes; `listRowBackground`
/// is scoped to the same rect the selection uses.
fileprivate struct RowHover: ViewModifier {
    let isSelected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerRadius: RowHover.selectionRadius)
                    .fill(Color.primary.opacity(hovering && !isSelected ? 0.12 : 0))
                    .padding(.horizontal, RowHover.selectionInset)
            )
            .onHover { hovering = $0 }
    }

    /// How far the system insets a sidebar row's selection capsule from the row
    /// rect. `listRowBackground` fills the whole row, so without this the wash
    /// lands wider than the selection on both sides and the two read as
    /// different shapes — visible the moment a hovered row sits next to a
    /// selected one. Not a public metric, so it is matched by eye against a
    /// running window rather than derived; re-check it if a future macOS moves
    /// the capsule.
    static let selectionInset: CGFloat = 10

    /// The capsule's corner radius, matched the same way and for the same
    /// reason: at 6 the wash was visibly squarer than the selection it sits
    /// beside.
    static let selectionRadius: CGFloat = 8
}

extension View {
    /// See `RowHover`. Apply **after** the row's `contentShape`, so the whole
    /// row lights up rather than just the text.
    fileprivate func rowHover(selected: Bool) -> some View {
        modifier(RowHover(isSelected: selected))
    }
}

/// A sidebar section header carrying the group-level layout override for one
/// media kind. Three states: an untouched group defers to the global rather than
/// pinning a mode, so setting the toolbar picker still moves everything.
///
/// The chip stays the in-context setter (2026-08-01, Daniel's call on sourced
/// research): it is the group rung's one reliable mouse-reachable control, and
/// the quiet inherited dress (see `ModeChipFace`) is what answers the
/// too-much-at-rest complaint — not removal. Two mirrors back it up: the
/// header's own context menu below, matching the rows' right-click grammar,
/// and Layout — TV / Layout — Movies in the View menu (`LayoutCommands`), the
/// HIG's required menu-bar home.
struct GroupModeHeader: View {
    let title: String
    let type: MediaType
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 6)
            ModeChip(
                current: model.groupOverride(for: type),
                inherited: model.globalMode,
                set: { model.setGroupOverride($0, for: type) }
            )
        }
        // A section header gets shallower List insets than the rows under it,
        // so unpadded the chip's trailing edge overshoots the rows' content
        // edge and the right-hand rhythm breaks at every header. Measured with
        // GeometryReader probes on a running window (2026-08-01): header
        // content ends at maxX 515.5, row content at 501.5 — 14pt exactly,
        // for both headers. A system metric, not a published one; re-measure
        // if a future macOS moves either inset (see `RowHover` for the same
        // caveat about the selection capsule).
        .padding(.trailing, 14)
        // Same reason as the rows: the Spacer is not hit-testable, so without
        // a shape the header's middle is dead to right-click.
        .contentShape(Rectangle())
        // Named like the row menus — see `ItemLayoutPicker.title` for why every
        // menu names its target. Verified firing on a macOS Section header on a
        // running window (2026-08-01) — it was an open question in the research.
        .contextMenu {
            LayoutPicker(
                title: "Layout — \(title)",
                current: model.groupOverride(for: type),
                inherited: model.globalMode,
                set: { model.setGroupOverride($0, for: type) }
            )
        }
    }
}

/// A TV show row: a disclosure chevron (when the show spans multiple seasons),
/// the show name, a season/file summary, and the row's passive status marks.
///
/// The name area is one button — a click selects the show (focusing every
/// season's files under a single title edit) and, for a multi-season show,
/// toggles its seasons open/closed. Clicking again keeps the show selected and
/// toggles back. (We drive selection in the button action instead of relying on
/// the List's tap, which a custom row gesture suppresses.)
///
/// The trailing marks sit **outside** that button. That started as a necessity —
/// a menu nested inside a row-wide button had to fight it for every click — and
/// survives its cause: the marks are inert now, but pulling them inside would
/// hand the button a click target that reports layout and does nothing about it.
struct ShowRow: View {
    let node: NodePlan
    let conflicts: Set<URL>
    let model: AppModel
    let expanded: Bool
    let canExpand: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 12)
                        .opacity(canExpand ? 1 : 0)

                    Image(systemName: "tv").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.displayTitle)
                            .lineLimit(1).truncationMode(.tail)
                            .help(node.displayTitle)
                        Text(node.seasonSummary)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Flags first, mark last. The mark is the one token that repeats
            // across rows, so it is the one that needs a column — and the
            // trailing-most view gets one for free, because the Spacer absorbs
            // every point of slack. Outboard variable-width flags were what
            // scattered it over nine x positions across a 111pt spread. The
            // flags carry colour and a glyph, so they stay findable unaligned.
            FlagBadges(node: node, conflicts: conflicts, compact: true)
            ItemModeMark(node: node, model: model)
        }
        .padding(.vertical, 2)
        // Spacer is not hit-testable and this HStack has neither a background
        // nor a shape of its own, so without this ~70% of the row is dead to
        // right-click. A shape, not a gesture — it does not re-open the
        // left-click contention described above.
        .contentShape(Rectangle())
        .rowHover(selected: model.selection == .item(node.source))
        // Named, not a bare "Layout" — a right-click need not move the List's
        // selection, so this menu and its View ▸ Layout mirror can point at
        // different rows at once. See `ItemLayoutPicker.title`.
        .contextMenu {
            ItemLayoutPicker(node: node, model: model,
                           title: "Layout — “\(node.displayTitle)”")
        }
    }
}

/// An indented season row under a show. Selecting it focuses just that season.
struct SeasonRow: View {
    let slice: SeasonSlice
    /// The show this season belongs to — the level its layout is actually set
    /// at, and what its context menu names.
    let show: NodePlan
    let conflicts: Set<URL>
    let model: AppModel

    private var conflicted: Bool { slice.sources.contains { conflicts.contains($0) } }

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 18)                 // indent under the show's icon
            VStack(alignment: .leading, spacing: 1) {
                Text("Season \(slice.number)").lineLimit(1)
                Text("\(slice.pairs.count) file\(slice.pairs.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if conflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(Palette.conflict)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .rowHover(selected: model.selection == .season(show: show.source,
                                                       number: slice.number))
        // No layout mark of its own — a season never carries a setting. But the
        // menu targets the parent show and says whose layout it is changing,
        // because a right-click that produced nothing here would teach the user
        // that seasons have no layout rather than that shows own it.
        .contextMenu {
            ItemLayoutPicker(node: show, model: model,
                           title: "Layout — “\(show.displayTitle)”")
        }
    }
}

struct AllItemsRow: View {
    let count: Int
    var selected = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("All items")
                Text("edit every title together")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .rowHover(selected: selected)
    }
}

struct SidebarRow: View {
    let node: NodePlan
    let conflicts: Set<URL>
    let model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.mediaType == .tv ? "tv" : "film")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                // The title, not the destination folder: a flattened movie has no
                // destination folder, and a row that silently switched to showing a
                // filename would read as a different kind of thing in each mode.
                Text(node.displayTitle)
                    .lineLimit(1).truncationMode(.middle)
                    .help(node.displayTitle)
                Text(node.originalName)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            FlagBadges(node: node, conflicts: conflicts, compact: true)
            ItemModeMark(node: node, model: model)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .rowHover(selected: model.selection == .item(node.source))
        // Named, not a bare "Layout" — a right-click need not move the List's
        // selection, so this menu and its View ▸ Layout mirror can point at
        // different rows at once. See `ItemLayoutPicker.title`.
        .contextMenu {
            ItemLayoutPicker(node: node, model: model,
                           title: "Layout — “\(node.displayTitle)”")
        }
    }
}

/// An `.unchanged` row that a deliberate layout override is holding in place —
/// forcing Folders onto an already-organised item leaves it nothing to do.
/// Unlike its muted siblings it stays selectable, so the override remains
/// visible and reversible instead of quietly stranding the item.
///
/// This row is **load-bearing, not decorative**: it is the only place a pinned
/// override on a node with no work left can be cleared. What satisfies that is
/// reachability of the *setter*, not a widget in the row — the row is
/// right-clickable and it is selectable, so `Layout ▸` and View ▸ Layout both
/// reach it.
struct PinnedRow: View {
    let node: NodePlan
    let conflicts: Set<URL>
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.mediaType == .tv ? "tv" : "film")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.displayTitle)
                    .lineLimit(1).truncationMode(.middle)
                    .help(node.displayTitle)
                Text("already named").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            // `isConflicted(in:)` is unit-aware, not move-aware, so a pinned
            // node sitting in a collision is flagged nowhere else in the app.
            // Junk self-suppresses on an `.unchanged` node; verify is real here.
            FlagBadges(node: node, conflicts: conflicts, compact: true)
            // Deliberately NOT gated by `statesOwnLayout`. This row exists only
            // when `hasSelectableRow` holds, which for an `.unchanged` node is
            // *exactly* `itemOverride != .inherit` — the gate's first disjunct.
            // The gate would be a tautology here; leaving it out means no future
            // edit to the visibility rule can strand an override with no cue.
            ModeBadge(mode: node.outputMode, explicit: true, showsWord: false)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .rowHover(selected: model.selection == .item(node.source))
        // Named, not a bare "Layout" — a right-click need not move the List's
        // selection, so this menu and its View ▸ Layout mirror can point at
        // different rows at once. See `ItemLayoutPicker.title`.
        .contextMenu {
            ItemLayoutPicker(node: node, model: model,
                           title: "Layout — “\(node.displayTitle)”")
        }
    }
}

struct MutedRow: View {
    let name: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The small flag badges shown on rows, cards, and the inspector header.
struct FlagBadges: View {
    let node: NodePlan
    let conflicts: Set<URL>
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if node.isConflicted(in: conflicts) {
                badge(compact ? "dup" : "duplicate", "exclamationmark.triangle.fill", Palette.conflict)
            }
            if !node.junk.isEmpty {
                badge("\(node.junk.count) junk", "trash", Palette.junk)
                    .monospacedDigit()
            }
            if node.needsVerify {
                badge(compact ? nil : "verify", "flag", Palette.verify)
                    .help(node.verifyHint)
            }
        }
    }

    private func badge(_ text: String?, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            // Without these the word wraps under compression: at the 250pt
            // minimum column "dup" stacks into three letters and the row's
            // height goes 34 → 82pt.
            if let text { Text(text).lineLimit(1).fixedSize() }
        }
        .font(.caption2)
        .foregroundStyle(color)
    }
}
