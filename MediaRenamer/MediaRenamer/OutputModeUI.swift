import SwiftUI
import RenamerCore

// MARK: - Vocabulary

/// One set of words and glyphs for the output mode, shared by the toolbar
/// picker, the group and item menus, the row badges, the preview band and the
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

    var symbol: String {
        switch self {
        case .organise:   return "folder"
        case .renameOnly: return "tray.full"
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

// MARK: - Badge

/// The mode a row's files will land in, as a small tinted capsule. Shown on every
/// rename row in **both** modes: a badge that appeared only when flattening would
/// make organise mode the unmarked default, and the whole point is that neither
/// mode is the silent one. An override is drawn slightly stronger, so "this item
/// was set deliberately" is distinguishable from "this item inherited".
struct ModeBadge: View {
    let mode: OutputMode
    var explicit = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: mode.symbol)
            Text(mode.name)
        }
        .font(.caption2)
        .fontWeight(explicit ? .semibold : .regular)
        .foregroundStyle(Palette.mode)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Palette.mode.opacity(explicit ? 0.18 : 0.10), in: Capsule())
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

// MARK: - Group / item control

/// The three-state override used at the group ("all TV", "all Movies") and item
/// levels. `Inherit` names the mode it currently resolves to, so choosing to
/// defer never leaves the outcome unstated.
struct ModeOverrideMenu: View {
    let current: ModeOverride
    /// The mode `.inherit` resolves to for this group/item right now.
    let inherited: OutputMode
    let set: (ModeOverride) -> Void
    /// Hides the leading "Layout" caption, for tight rows like a section header.
    var compact = false

    private var effective: OutputMode { current.forced ?? inherited }

    var body: some View {
        HStack(spacing: 3) {
            if !compact {
                Text("Layout").font(.caption).foregroundStyle(.secondary)
            }
            // The badge sits OUTSIDE the menu on purpose. As a `Menu` label it gets
            // re-styled as button content — the tint and the capsule are dropped —
            // which silently erases the one thing the weight was carrying: whether
            // this level is pinned or inheriting. Keeping the badge as an ordinary
            // view preserves that, and leaves the menu as a plain disclosure.
            ModeBadge(mode: effective, explicit: current != .inherit)
            Menu {
                Picker("Layout", selection: Binding(get: { current }, set: set)) {
                    Text("Inherit — \(inherited.name)").tag(ModeOverride.inherit)
                    Text(OutputMode.organise.name).tag(ModeOverride.organise)
                    Text(OutputMode.renameOnly.name).tag(ModeOverride.renameOnly)
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "chevron.down").font(.caption2)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
            .contentShape(Rectangle())
        }
        .help(current == .inherit
              ? "Inheriting — \(effective.name). Files land \(effective.detail)."
              : "Set to \(effective.name). Files land \(effective.detail).")
    }
}
