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
    /// Reserve and draw a disclosure chevron. A chip that never moves reads as a
    /// badge — which is exactly why the item control went unnoticed in the
    /// inspector — so the interactive one always shows its chevron and brightens
    /// the whole capsule on hover.
    var interactive = false
    var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: mode.symbol)
            Text(mode.name)
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
    }

    private var fill: Double {
        if pinned { return hovering ? 0.30 : 0.22 }
        return hovering ? 0.20 : 0.10
    }
}

/// A read-only layout indicator, for the surfaces that report the mode rather
/// than set it: the inspector header and the All-items cards.
struct ModeBadge: View {
    let mode: OutputMode
    var explicit = false

    var body: some View {
        ModeChipFace(mode: mode, pinned: explicit)
            .accessibilityElement()
            .accessibilityLabel("Layout")
            .accessibilityValue(explicit ? "\(mode.name), set here" : "\(mode.name), inherited")
    }
}

/// The three-state layout control: defer to the level above, or pin one of the
/// two modes. `Inherit` names the mode it currently resolves to, so choosing to
/// defer never leaves the outcome unstated.
///
/// **One component at both densities.** The sidebar section headers (group
/// level) and the show/movie rows (item level) render the same chip, because a
/// row control that looked different from the header control would read as a
/// different kind of thing — and the point of putting them in one place is that
/// they are one thing at three scopes.
///
/// **The menu is an invisible overlay, not the chip's label.** A `Menu`
/// restyles its label as button content and drops the tint and the capsule with
/// it — that is a property of this codebase, observed when the control was first
/// built, and it is why the old version had to keep its badge outside the menu
/// and settle for a 16pt chevron as the only clickable part. Laying a
/// clear-labelled menu over an ordinary chip sidesteps the question rather than
/// betting on a menu style: the label has no styling left to lose, the chip
/// renders exactly as `ModeBadge` does, and the click target is the whole
/// capsule.
struct ModeChip: View {
    let current: ModeOverride
    /// The mode `.inherit` resolves to for this group/item right now.
    let inherited: OutputMode
    let set: (ModeOverride) -> Void

    @State private var hovering = false

    private var effective: OutputMode { current.forced ?? inherited }
    private var pinned: Bool { current != .inherit }

    var body: some View {
        ModeChipFace(mode: effective, pinned: pinned,
                     interactive: true, hovering: hovering)
            .overlay {
                Menu {
                    Picker("Layout", selection: Binding(get: { current }, set: set)) {
                        Text("Inherit — \(inherited.name)").tag(ModeOverride.inherit)
                        Text(OutputMode.organise.name).tag(ModeOverride.organise)
                        Text(OutputMode.renameOnly.name).tag(ModeOverride.renameOnly)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .onHover { hovering = $0 }
            .help(pinned
                  ? "Layout set here — \(effective.name). Files land \(effective.detail). Choose “Inherit” to clear it."
                  : "Layout inherited — \(effective.name). Files land \(effective.detail).")
            .accessibilityLabel("Layout")
            .accessibilityValue(pinned ? "\(effective.name), set here"
                                       : "\(effective.name), inherited")
    }
}

/// The row-level layout control, wired to one node's slot in the cascade. Every
/// sidebar row that can carry an override renders this, so the three of them
/// cannot drift apart.
struct ItemModeChip: View {
    let node: NodePlan
    let model: AppModel

    var body: some View {
        ModeChip(current: model.itemOverride(for: node.source),
                 inherited: model.inheritedMode(for: node),
                 set: { model.setItemOverride($0, for: node.source) })
    }
}

// MARK: - Global control (toolbar)

/// The plan-wide layout. Two states, both always visible, so the active one is
/// legible at a glance rather than hidden behind a menu. Rendered only once a
/// folder is loaded — there is nothing to lay out before that.
struct GlobalModePicker: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Layout").font(.callout).foregroundStyle(.secondary)
            Picker("Layout", selection: Binding(
                get: { model.globalMode },
                set: { model.setGlobalMode($0) }
            )) {
                ForEach(OutputMode.allCases, id: \.self) { mode in
                    Text(mode.name).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        }
        .help("How every item is laid out under the chosen folder. "
              + "The TV and Movies headers, and each row, can override this.")
    }
}
