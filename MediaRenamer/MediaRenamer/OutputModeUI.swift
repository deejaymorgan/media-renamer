import SwiftUI
import RenamerCore

// MARK: - Vocabulary

/// One set of words, glyphs and colours for the output mode, shared by the
/// toolbar picker, the group and row controls, the preview band and the
/// confirmation dialog — so the mode is named the same way everywhere it appears
/// and the two modes always read as siblings rather than as a default and an
/// exception.
extension OutputMode {
    /// The one word this mode is called, everywhere: control segments, menu
    /// items, row chips, destination bands, the confirmation dialog.
    ///
    /// It names the **result**, not the setting — what the folder ends up
    /// looking like — which is why there is only one word rather than a separate
    /// control name and badge word. The engine's own case names (`organise` /
    /// `renameOnly`) are API and stay as they are; "Rename only" was a slightly
    /// false label for the UI anyway, since flat mode also *moves* files up out
    /// of subfolders and removes the emptied ones.
    var name: String {
        switch self {
        case .organise:   return "Folders"
        case .renameOnly: return "Flat"
        }
    }

    /// What the resulting shape is, as a clause that follows the file count:
    /// "12 files <detail>".
    var detail: String {
        switch self {
        case .organise:   return "into Show/Season and Movie (Year) folders"
        case .renameOnly: return "directly into the chosen folder, with no folder tree"
        }
    }

    /// The chip glyph. A folder against a plain list — "a list where folders
    /// would be" — rather than the old `tray.full`, which read as a container
    /// (an inbox, a pile) when the whole point of flat mode is that there is no
    /// container.
    var symbol: String {
        switch self {
        case .organise:   return "folder"
        case .renameOnly: return "list.bullet"
        }
    }

    /// The variant used in the destination band, where the glyph sits at
    /// `callout` and wants more weight. Most list symbols have no `.fill`
    /// counterpart, so the flat side stays the same glyph and lets the tint
    /// carry the weight — an asymmetry several badge glyphs already have.
    var bandSymbol: String {
        switch self {
        case .organise:   return "folder.fill"
        case .renameOnly: return symbol
        }
    }

    /// Blue for Folders, teal for Flat. See `Palette` for why the two modes
    /// stopped sharing one tint.
    var tint: Color {
        switch self {
        case .organise:   return Palette.folders
        case .renameOnly: return Palette.flat
        }
    }
}

extension ModeOverride {
    var name: String {
        switch self {
        case .inherit:    return "Inherit"
        case .organise:   return OutputMode.organise.name
        case .renameOnly: return OutputMode.renameOnly.name
        }
    }
}

// MARK: - The chip

/// The face every layout chip wears, interactive or not: the mode's glyph and
/// word in the mode's tint, inside a capsule.
///
/// **Pinned and inherited are different states, not different weights.** A
/// pinned chip is bordered and filled; an inherited one is a soft wash with no
/// border. The previous cue — semibold text over an 0.18-vs-0.10 background —
/// was invisible in practice, which is how a plan could carry overrides nobody
/// could see. Weight still rides along, but the border is what carries it.
private struct ModeChipFace: View {
    let mode: OutputMode
    /// Set deliberately at this level, rather than inherited from above.
    let pinned: Bool
    /// Draw the mode's word beside its glyph. Sidebar row marks drop it: four
    /// capsules repeating one word is noise, and glyph-only makes both modes the
    /// same width, so every mark in the list shares a left *and* a right edge
    /// with no reserved slot. The section header directly above keeps glyph +
    /// word and acts as the legend; the word also survives in the tooltip, the
    /// accessibility value, the destination band, the inspector and the Apply
    /// dialog.
    var showsWord = true
    /// Reserve and draw a disclosure chevron. A chip that never moves reads as a
    /// badge — which is exactly why the item control went unnoticed in the
    /// inspector — so the interactive one always shows its chevron and brightens
    /// the whole capsule on hover.
    var interactive = false
    var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: mode.symbol)
            if showsWord {
                // Without these the word wraps under compression: at the 250pt
                // minimum column the chip collapses to "≡ … ⌄".
                Text(mode.name).lineLimit(1).fixedSize()
            }
            if interactive {
                Image(systemName: "chevron.down")
                    .opacity(hovering ? 0.9 : 0.4)
            }
        }
        .font(.caption2)
        .fontWeight(pinned ? .semibold : .regular)
        .foregroundStyle(mode.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule()
                .fill(mode.tint.opacity(fill))
                .overlay(
                    Capsule().strokeBorder(mode.tint.opacity(pinned ? 0.85 : 0),
                                           lineWidth: 1)
                )
        }
        // The face holds its intrinsic size rather than accepting a squeeze.
        // Measured: under a narrow proposal it otherwise wraps and deforms
        // (43 × 95 at a 30pt proposal); with this it stays 79 × 17 and the
        // neighbouring title truncates instead, which is the right trade in
        // every placement. It sits on the *face*, not on `ModeChip`, so the
        // passive `ModeBadge` — which lives in width-constrained sidebar rows
        // and never opens a menu — inherits the same guard. Load-bearing under
        // `ModeChip` in particular: there the drawn face *is* the hit target,
        // so a container-driven distortion of the face distorts the target.
        .fixedSize()
    }

    private var fill: Double {
        if pinned { return hovering ? 0.30 : 0.22 }
        return hovering ? 0.20 : 0.10
    }
}

/// A read-only layout indicator, for the surfaces that report the mode rather
/// than set it: the inspector header, the All-items cards, and the sidebar rows
/// (where it is the *mark*, and the setting lives in the row's context menu).
///
/// Never clickable, on any surface. That is the point of splitting it from
/// `ModeChip`: a sidebar row's trailing gutter is a status area — `dup`, `N
/// junk`, verify — and a control mixed in among them, at the same size and with
/// no visual rule separating the categories, leaves the eye unable to tell which
/// of the four things it can press.
struct ModeBadge: View {
    let mode: OutputMode
    var explicit = false
    /// Glyph only, no word. See `ModeChipFace.showsWord` — the word is never
    /// lost, only moved to the tooltip and the accessibility value.
    var showsWord = true

    var body: some View {
        ModeChipFace(mode: mode, pinned: explicit, showsWord: showsWord)
            .accessibilityElement()
            .accessibilityLabel("Layout")
            // These two name the mode in full whether or not the word is drawn.
            // For a glyph-only mark they are where the word actually lives, so
            // `.help` goes *outside* `.accessibilityElement()`, which would
            // otherwise ignore the hint it contributes.
            .accessibilityValue(explicit ? "\(mode.name), set here" : "\(mode.name), inherited")
            .help(explicit
                  ? "Layout set here — \(mode.name). Files land \(mode.detail)."
                  : "Layout inherited — \(mode.name). Files land \(mode.detail).")
    }
}

/// The three layout choices as a bare picker: defer to the level above, or pin
/// one of the two modes. `Inherit` names the mode it currently resolves to, so
/// choosing to defer never leaves the outcome unstated.
///
/// Extracted so the chip's menu, a sidebar row's context menu and View ▸ Layout
/// render **one** control rather than three copies to keep in step. `.inline`
/// draws correctly in all three on macOS 14.
struct LayoutPicker: View {
    /// The picker's own label. An `.inline` picker draws it as the section
    /// heading above the choices, which is how a row's context menu names the
    /// row it is about to change without spending a submenu on it.
    var title = "Layout"
    let current: ModeOverride
    /// The mode `.inherit` resolves to for this group/item right now.
    let inherited: OutputMode
    let set: (ModeOverride) -> Void

    var body: some View {
        Picker(title, selection: Binding(get: { current }, set: set)) {
            Text("Inherit — \(inherited.name)").tag(ModeOverride.inherit)
            Text(OutputMode.organise.name).tag(ModeOverride.organise)
            Text(OutputMode.renameOnly.name).tag(ModeOverride.renameOnly)
        }
        .pickerStyle(.inline)
    }
}

/// The three-state layout control as a chip: defer to the level above, or pin
/// one of the two modes.
///
/// **The group rung only.** Section headers render this; rows do not. A row is a
/// place to *show* state, not to *set* a three-way setting — and this chip is
/// ~16pt tall against the HIG's 20×20pt minimum for a macOS control, which a
/// header can carry (it holds nothing else) and a row cannot justify. So rows
/// carry a passive `ModeBadge` and reach the setting through their context menu
/// and View ▸ Layout, while the header chip stays interactive and doubles as the
/// standing worked example of the control's shape and vocabulary for the marks
/// below it.
///
/// **The chip is the menu's own label.** The obvious reading of the earlier
/// problem — "a `Menu` restyles its label and drops the tint and the capsule" —
/// was half right, and the half it got wrong cost the control its hit target.
/// The styling *is* destroyed by `.menuStyle(.borderlessButton)`, and by
/// `.menuStyle(.button)` without a button style; it survives intact under
/// `.menuStyle(.button)` + `.buttonStyle(.plain)`, which is therefore
/// load-bearing rather than cosmetic. Laying a clear-labelled menu *over* the
/// chip looked like a way to sidestep that question, but an overlay is a second
/// layout pass sized by its container rather than by the shape underneath, and a
/// bare `Shape` has no intrinsic size to give it: the clickable region measured
/// **6 × 14pt inside a 78.75 × 17pt capsule** — about 6% of what was drawn, dead
/// centre. Against the HIG's 20 × 20pt minimum that is not a small target, it is
/// a broken one, and `.onHover` brightening the *whole* capsule meant the chip
/// actively lied about where to click.
///
/// So the face is the label and the target is the drawn shape by construction.
/// `.contentShape(Rectangle())` rather than `Capsule()` deliberately: the hover
/// frame is rectangular, and matching it exactly is worth more than the ~2pt
/// corner slivers a capsule would (honestly) exclude. No invisible halo — in a
/// dense row a halo steals clicks from its neighbours; if the target is ever
/// judged too small, grow the *drawn* chip.
struct ModeChip: View {
    let current: ModeOverride
    /// The mode `.inherit` resolves to for this group/item right now.
    let inherited: OutputMode
    let set: (ModeOverride) -> Void

    @State private var hovering = false

    private var effective: OutputMode { current.forced ?? inherited }
    private var pinned: Bool { current != .inherit }

    var body: some View {
        Menu {
            LayoutPicker(current: current, inherited: inherited, set: set)
        } label: {
            ModeChipFace(mode: effective, pinned: pinned,
                         interactive: true, hovering: hovering)
                .contentShape(Rectangle())
        }
            .menuStyle(.button)
            // Not optional. Without it the chip is redrawn as a bordered push
            // button and the face stops being what you press. See above.
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .onHover { hovering = $0 }
            .help(pinned
                  ? "Layout set here — \(effective.name). Files land \(effective.detail). Choose “Inherit” to clear it."
                  : "Layout inherited — \(effective.name). Files land \(effective.detail).")
            .accessibilityLabel("Layout")
            .accessibilityValue(pinned ? "\(effective.name), set here"
                                       : "\(effective.name), inherited")
    }
}

/// The row-level layout **mark**: the resolved mode's glyph, and only on a row
/// whose layout the toolbar does not already state (`AppModel.statesOwnLayout`).
/// Passive — it joins `dup`, `N junk` and verify as one consistent category of
/// inert status, which is what lets the gutter be read at a glance.
///
/// Every row that can carry an override renders this, so the three of them
/// cannot drift apart. `PinnedRow` is the deliberate exception: see there.
struct ItemModeMark: View {
    let node: NodePlan
    let model: AppModel

    @ViewBuilder
    var body: some View {
        if model.statesOwnLayout(node) {
            ModeBadge(mode: node.outputMode,
                      explicit: model.itemOverride(for: node.source) != .inherit,
                      showsWord: false)
        }
    }
}

/// The row-level layout **control**, in its new home: the row's context menu,
/// mirrored by View ▸ Layout on the selection.
///
/// Right-click is a legitimate primary home on macOS precisely because the HIG
/// requires the mirror — *"always make context menu items available in the main
/// interface, too"* — so the pair is more idiomatic than a control on every row,
/// not less. It is also what Mail does with mailbox behaviours and Finder with
/// tags: the row shows state, the menus set it.
///
/// **Flat, not a `Layout ▸` submenu.** Layout is the only thing a sidebar row's
/// context menu offers, and nesting one item under one heading spends a click
/// and a hover-open on a branch that never forks. The `.inline` picker draws
/// `title` as its section heading instead, so the menu still says whose layout
/// it is about to change while putting the three choices one click from the
/// right-click. If a row ever gains a second unrelated command, this becomes a
/// `Menu` again and the heading becomes its title — but not before.
struct ItemLayoutPicker: View {
    let node: NodePlan
    let model: AppModel
    /// What the picker says it will change, drawn as its section heading.
    /// **Required, with no default** — every
    /// caller must name its target. Season rows have to, because layout is
    /// show-scoped (one override per show, never per season) and a bare "Layout"
    /// there would misstate what it reaches. Item rows have to for a subtler
    /// reason: a right-click does not necessarily move `List` selection, so this
    /// picker and its View ▸ Layout mirror can be pointed at different nodes at the
    /// same instant, and only one of them saying so is how a user changes the
    /// mode on a row they were not looking at. Naming the target also puts the
    /// axis word "Layout" one right-click away on every row, which is where it
    /// earns its keep now that no surface draws it at rest.
    let title: String

    var body: some View {
        LayoutPicker(
            title: title,
            current: model.itemOverride(for: node.source),
            inherited: model.inheritedMode(for: node),
            set: { model.setItemOverride($0, for: node.source) }
        )
    }
}

// MARK: - Global control (toolbar)

/// The plan-wide layout. Two states, both always visible, so the active one is
/// legible at a glance rather than hidden behind a menu. Rendered only once a
/// folder is loaded — there is nothing to lay out before that.
///
/// **One hit target per toolbar item, sized by the system.** The rule is about
/// what can be *pressed*, not about how many views are present: the sibling
/// `OverridesIndicator` pairs an inert count with one button in a single item and
/// satisfies it, because the count is a status string and not a second control.
/// (Merging the two into one wide `Label` button would break the rule the other
/// way, by giving an action with no undo a 114pt target.) What the toolbar's
/// control metrics and its overflow arithmetic care about is the pressable
/// region, so that is what the rule counts.
///
/// **The item is the control and nothing else.** On macOS 26 the segmented
/// picker draws no border of its own — no dividers, no surrounding capsule, just
/// a filled pill on the selected segment — and relies on the toolbar item's
/// glass container to be its frame. So a caption sharing the item does not sit
/// in an outer pill around the control; it sits *level with the segments, inside
/// the picker's own frame*, and reads as an inert third segment that happens to
/// do nothing when clicked. The visible `Layout` caption that used to lead this
/// item is gone for that reason, and the tooltip now opens with the word, since
/// it became the place the axis is named. Anything else added back into this
/// item will land inside the segments again.
///
/// **The width is the control's own.** A hardcoded one is a landmine: the
/// previous `190` was 18pt *narrower* than `Organise / Rename only`'s 208pt
/// intrinsic, so it was quietly squeezing, and last round's 190 → 140 happened
/// to land exactly on `Folders / Flat`'s 140pt intrinsic — which is why nothing
/// looked wrong. The next vocabulary change would have reintroduced the squeeze
/// just as invisibly.
///
/// **Dropping the caption improved accessibility rather than costing it.**
/// `.labelsHidden()` does not affect accessibility, so the picker keeps its own
/// "Layout" label; the decorative `Text` was an unassociated static string that
/// VoiceOver announced as a second one. Do not add a visible caption back — see
/// above for what it renders as.
///
/// **The segments are words only, and not for want of trying.** Adding the mode
/// glyph here was wanted: the sidebar's row marks are glyph-only, so the
/// glyph→mode pairing needs teaching somewhere permanent, and this is the only
/// layout surface that never scrolls — `List` section headers do not stick
/// (probed: `floatsGroupRows == false`), so the header chip is off screen on
/// exactly the scrolled-override screen the marks exist for.
///
/// A macOS segmented `Picker` will not draw a glyph and a word in one segment.
/// Three constructions, all built and read off a running window (2026-08-01):
///
/// | segment content | renders as |
/// |---|---|
/// | `Label(name, systemImage:)` | **icon only** — the words vanish |
/// | the same, `.labelStyle(.titleAndIcon)` | **text only** — the glyph vanishes |
/// | `HStack { Image; Text }` | **mangled** — the glyph is promoted to its own third segment |
///
/// Icon-only is the one outcome 39a37bd explicitly rejected, since it reverses
/// 1059d8e's rule that the layout words appear on every surface, segments
/// included; so words win and the glyph does not appear here. Do not retry this
/// with another label style — the control is `NSSegmentedControl` underneath and
/// takes one of title *or* image per segment.
///
/// **Closed, not pending.** Glyph + word here would need an `NSViewRepresentable`
/// around a real `NSSegmentedControl`, and the app stays in SwiftUI (Daniel,
/// 2026-08-01). So this surface will not become the legend, and the same ruling
/// settles the segments' uneven widths — `Folders` is about twice the string
/// `Flat` is, that is content-fit behaviour, and equalising it needs
/// `segmentDistribution` on the same bridge. Both are accepted as they are
/// rather than deferred.
///
/// The pairing is carried instead by the mark's tooltip, the inspector badge,
/// the section-header chip and the destination band — all of which draw glyph
/// and word together. Whether that is enough at rest — none of the four is
/// visible without hovering, selecting or scrolling to a header — was the open
/// question, about *teaching the marks* rather than this control, and it was
/// examined and **closed on 2026-08-01 (ux-polish-3)**: the pairing stays
/// hover-taught, the bottom bar's layout chips add a standing glyph+word+tint
/// summary accepted on its own merits as a plan summary (not a teaching
/// surface), and no further teaching work is planned. Do not reopen it — no
/// tips, hints, legends or other discoverability surface is deferred; they are
/// crossed off.
struct GlobalModePicker: View {
    let model: AppModel

    var body: some View {
        Picker("Layout", selection: Binding(
            get: { model.globalMode },
            set: { model.setGlobalMode($0) }
        )) {
            ForEach(OutputMode.allCases, id: \.self) { mode in
                // Glyph *and* word. The sidebar's row marks are glyph-only —
                // four capsules repeating one word is noise — which leaves the
                // glyph→mode pairing to be taught somewhere permanent, and the
                // section-header chip cannot be that somewhere: macOS `List`
                // headers do not stick (probed: `floatsGroupRows == false`), so
                // on the one screen the marks exist for — an override, scrolled
                // — the legend is off screen by construction. This item never
                // scrolls, so it is the legend. Teach the pairing where there is
                // room, abbreviate where there is not; Finder tags and Mail
                // flags do the same. Not the icon-only segments 39a37bd
                // rejected: the word stays in both, so 1059d8e's rule that the
                // layout words appear on every surface still holds literally.
                Text(mode.name).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // No explicit `.accessibilityLabel` here: `Picker("Layout", …)` already
        // supplies one and `.labelsHidden()` is visual only, so adding a second
        // is at best redundant — and at worst it flattens a container of
        // accessibility elements into one, which would cost VoiceOver the
        // ability to move between the two segments. `ModeBadge` is the opposite
        // case and labels itself deliberately: it is a leaf, not a container.
        .help("Layout — how every item is laid out under the chosen folder. "
              + "The TV and Movies headers override it for a media kind; "
              + "right-click a row, or use View ▸ Layout, for one item.")
    }
}
