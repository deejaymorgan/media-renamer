import SwiftUI
import UniformTypeIdentifiers
import RenamerCore

/// The window's content width, reported up from a `.background` reader so the
/// sidebar's maximum can be half of it. A preference rather than a shared
/// `GeometryReader` wrapper: the wrapper would sit between the window and the
/// split view and change what is being measured.
private struct WindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    @State private var model = AppModel()
    @State private var importing = false
    @State private var confirming = false
    @State private var showResult = false
    /// See `WindowWidthKey`. Seeded at the window's own floor so the first
    /// layout pass caps the column sensibly rather than at the 420 fallback.
    @State private var windowWidth: CGFloat = 1160

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(model: model)
                    // The `max` is load-bearing, not taste. Without it the column
                    // has no upper bound, so it can be dragged until the detail
                    // region is too narrow to lay the toolbar out — and the
                    // trailing `.primaryAction` items collapse into a `»` overflow
                    // menu, taking the layout picker with them. The split position
                    // persists across launches, so one careless drag hides the
                    // picker permanently until it is dragged back.
                    //
                    // `AppModel.statesOwnLayout` now depends on this: it
                    // suppresses every row's layout mark on a plan where nothing
                    // overrides, on the grounds that the toolbar already says it.
                    // Losing the picker there would leave the active layout
                    // stated nowhere at all, so this cap and the `minWidth`
                    // below are what make that suppression safe.
                    //
                    // Half the window rather than a fixed 420, so the column
                    // grows with the space available instead of freezing at a
                    // number chosen for the smallest allowed window. Half is
                    // also what makes the bound self-maintaining: the toolbar
                    // needs `sidebar + 510`, so a sidebar of `W/2` is safe for
                    // every `W ≥ 1020` — no per-width arithmetic, and no way for
                    // a wider window to reintroduce the overflow. `minWidth`
                    // below carries the headroom on top of that. The 420 floor
                    // only matters before the first geometry reading lands.
                    .navigationSplitViewColumnWidth(
                        min: 250, ideal: 300, max: max(420, windowWidth / 2))
            } detail: {
                DetailView(model: model)
            }
            .navigationTitle("Media Renamer")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { importing = true } label: {
                        Label("Choose Folder…", systemImage: "folder")
                    }
                }
                // The global layout, visible whenever there is a plan to lay out.
                // Deliberately absent from the empty state: with no folder chosen
                // there is nothing for it to describe.
                if model.plan != nil {
                    ToolbarItem(placement: .primaryAction) {
                        GlobalModePicker(model: model)
                    }
                    // Sits after the picker because it qualifies it: "…and N
                    // places are ignoring this." Provides its own toolbar items
                    // — the count and the reset button are separate ones now.
                    OverridesIndicator(model: model)
                }
            }

            // Acronym controls sit just above the apply bar, shown only when
            // there are all-caps words to decide. A bottom sibling avoids the
            // macOS 26 split-view safe-area bug that forced the old title-bar
            // accessory (`AcronymTitlebar`, deleted in ef2db05).
            if !model.acronymWords.isEmpty {
                Divider()
                AcronymBar(model: model)
            }
            Divider()
            BottomBar(model: model) { confirming = true }
        }
        // Measured, the toolbar needs roughly `sidebar + 510` to lay both
        // trailing items out. With the half-the-window cap above, `sidebar` is at
        // most `W/2`, so the binding constraint is `W/2 + 510 ≤ W` — i.e. 1020.
        // 1160 is that plus headroom for the toolbar's own content: swapping the
        // picker's labels back to `Organise / Rename only` costs 68pt of
        // intrinsic width, which makes the requirement `W/2 + 578 ≤ W`, i.e.
        // 1156. At 1020 that change would have reintroduced the overflow
        // invisibly — the same landmine 39a37bd removed when it deleted the
        // hardcoded `.frame(width: 140)`.
        .frame(minWidth: 1160, minHeight: 640)
        // Reads the window's content width for the column cap above. A
        // `GeometryReader` in a `.background` measures without proposing, so it
        // cannot disturb the split view's own layout — the same technique the
        // toolbar probes in `notes/` use, and deliberately not a wrapper around
        // `NavigationSplitView`, which changed the layout under test when
        // e050b09 was being measured.
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: WindowWidthKey.self,
                                       value: geo.size.width)
            }
        }
        .onPreferenceChange(WindowWidthKey.self) { windowWidth = $0 }
        .focusedSceneValue(\.appModel, model)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                model.choose(url)
            }
        }
        .confirmationDialog(applyTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button("Apply Renames") {
                model.apply()
                showResult = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(applyPrompt)
        }
        .alert("Apply complete", isPresented: $showResult) {
            Button("OK") { }
        } message: {
            Text(model.lastResultSummary ?? "Nothing to do.")
        }
    }

    private var subtitle: String {
        guard let plan = model.plan, let url = model.folderURL else {
            return "No folder chosen"
        }
        let n = plan.nodes.filter { $0.status == .rename }.count
        return "\(url.path) · \(count(n, "item"))"
    }

    // MARK: - The apply guard

    // Rename-only flattens, and it is the default at every launch — so the shape
    // of the result must be stated before Apply, not left to be inferred from the
    // preview. The title names the layout, the message counts the files per layout
    // and the source folders that will disappear. Both modes get the same sentence
    // shape and the same prominence: the risk of unnoticed flattening is real, but
    // so is the risk of a staging folder quietly sprouting a folder tree, and
    // loading one side with extra friction would train the user to click through.

    /// The layout, named in the dialog's title so it cannot be skipped past.
    private var applyTitle: String {
        let (organise, flat) = model.fileCountsByMode
        if organise > 0 && flat > 0 { return "Apply — mixed layout?" }
        if flat > 0 { return "Apply — flat, no folder tree?" }
        return "Apply — into folders?"
    }

    private var applyPrompt: String {
        let (organise, flat) = model.fileCountsByMode
        guard organise + flat > 0 else { return "Nothing to move." }
        let root = model.rootName.isEmpty ? "the chosen folder" : model.rootName

        var lines: [String] = []
        let clauses = [(organise, OutputMode.organise), (flat, OutputMode.renameOnly)]
            .filter { $0.0 > 0 }
            .map { landingClause($0.0, $0.1, root: root) }
        lines.append("Move " + clauses.joined(separator: ", and ") + ".")

        var consequences: [String] = []
        if model.folderRemovalCount > 0 {
            // An upper bound on purpose: the executor removes a source folder only
            // if it is genuinely empty once its files have moved, so kept junk or a
            // skipped file leaves it in place.
            consequences.append("Up to \(count(model.folderRemovalCount, "emptied source folder")) "
                                + "will be removed.")
        }
        let junk = model.junkToTrash.count
        if junk > 0 {
            consequences.append("\(count(junk, "junk file")) \(junk == 1 ? "goes" : "go") to the Trash.")
        }
        if !consequences.isEmpty { lines.append(consequences.joined(separator: " ")) }

        lines.append("Renaming never overwrites; conflicted items are skipped.")
        return lines.joined(separator: "\n\n")
    }

    /// "12 files directly into “Staging”, with no folder tree" — the same shape for
    /// either mode, so a mixed plan reads as one sentence naming both.
    private func landingClause(_ files: Int, _ mode: OutputMode, root: String) -> String {
        let n = count(files, "file")
        switch mode {
        case .organise:   return "\(n) into \(organisedShape) folders inside “\(root)”"
        case .renameOnly: return "\(n) directly into “\(root)”, with no folder tree"
        }
    }

    /// The tree the organised half will actually build. Naming a shape that will
    /// not exist ("Movie (Year)" when only TV is organised) is a small lie in the
    /// one dialog that has to be trusted absolutely.
    private var organisedShape: String {
        switch model.organisedKinds {
        case (true, false):  return "Show/Season"
        case (false, true):  return "Movie (Year)"
        default:             return "Show/Season and Movie (Year)"
        }
    }

}

/// "1 file" / "12 files". File-scope so the bottom bar and the window subtitle
/// pluralise through the same helper the confirmation dialog does, rather than
/// hardcoding an "s" and reading "1 files".
private func count(_ n: Int, _ noun: String) -> String {
    "\(n) \(noun)\(n == 1 ? "" : "s")"
}

// MARK: - Overrides indicator (toolbar, beside the layout picker)

/// How many levels are overriding the global layout, and one click to clear them
/// all. Absent when the cascade is uniform — there is nothing to report.
///
/// Overrides are the one edit layer that outlives an Apply, and a group whose
/// items have all been renamed keeps its section on screen purely so its header
/// control stays reachable. Both make it easy to be running a layout you no
/// longer remember choosing, in a place you would have to go looking for. This
/// is the folder-independent surface that says so and undoes it.
///
/// **The count is status and wears no glass (decided 2026-08-01).** Count and
/// button used to share one toolbar item, fused inside a single glass capsule —
/// which dressed an inert string as half of a control. WWDC25's macOS design
/// session (310) is direct about exactly that arrangement: "Non-interactive
/// items like custom titles and status indicators should avoid the glass
/// material. … With the glass material backing, it almost looks like a button."
/// So the count is its own toolbar item with its glass hidden
/// (`sharedBackgroundVisibility(.hidden)` — Apple's own doc example de-glasses
/// an inert `BuildStatus()` view), a fixed `ToolbarSpacer` holds the gap, and
/// the reset button stands alone on the glass. The *placement* survives on the
/// HIG's feedback guidance: status belongs beside the control that clears it,
/// as with Mail's toolbar count. The hand-measured interior padding that
/// balanced the old shared capsule (14/7/14) went with the capsule — the
/// system now owns every inset, so none of its numbers can go stale. Do not
/// re-fuse the pair for tidiness. Before macOS 26 there is no glass container
/// to decline, so the pair simply shares one unpadded item there.
struct OverridesIndicator: ToolbarContent {
    let model: AppModel

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if model.overrideCount > 0 {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    countLabel
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    resetButton
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 0) {
                        countLabel
                        resetButton
                    }
                }
            }
        }
    }

    private var countLabel: some View {
        Text(count(model.overrideCount, "override"))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .help("\(count(model.overrideCount, "layout override")) in force.")
    }

    private var resetButton: some View {
        Button {
            model.resetAllOverrides()
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        // No `.buttonStyle(.borderless)`: it opts the button out of toolbar
        // control metrics and collapses its item to 14pt beside 36pt native
        // ones. `.secondary` on the count carries the hierarchy without
        // shrinking anything.
        .accessibilityLabel("Reset all layout overrides")
        .help("Reset returns every TV, Movies and row setting to inheriting.")
    }
}

// MARK: - Summary chips (bottom bar, leading)

/// The plan's shape, then its composition: two layout chips (how many items
/// land Folders-style vs Flat), then the per-category breakdown, rendered as
/// colour-coded chips at the leading edge of the bottom bar (Apply and the
/// status note sit trailing). Only non-empty categories show, so the row stays
/// tight on small folders — a uniform plan therefore shows one layout chip.
/// All of them are status, not controls; none is clickable.
struct SummaryChips: View {
    let model: AppModel

    var body: some View {
        if let plan = model.plan {
            let g = PlanGroups(plan)
            // Item counts, like the TV/Movies chips beside them — not
            // `fileCountsByMode`, which counts files and is the apply
            // dialog's source.
            let renaming = plan.nodes.filter { $0.status == .rename }
            HStack(spacing: 8) {
                chip(OutputMode.organise.name,
                     renaming.filter { $0.outputMode == .organise }.count,
                     Palette.folders, symbol: OutputMode.organise.symbol)
                    .help(layoutHelp(.organise))
                chip(OutputMode.renameOnly.name,
                     renaming.filter { $0.outputMode == .renameOnly }.count,
                     Palette.flat, symbol: OutputMode.renameOnly.symbol)
                    .help(layoutHelp(.renameOnly))
                chip("TV", g.tvRename.count, Palette.tv)
                chip("Movies", g.movieRename.count, Palette.movie)
                chip("Unchanged", g.unchanged.count, nil)
                chip("Skipped", g.skipped.count, nil)
                chip("Conflicts", plan.conflicts.count, Palette.conflict)
                chip("Junk", g.junkCount, Palette.junk)
            }
        }
    }

    /// `OutputMode.detail` is a clause built to follow a count, not a full
    /// sentence — compose around it so both modes get the same sentence shape.
    private func layoutHelp(_ mode: OutputMode) -> String {
        "\(mode.name) — files land \(mode.detail)."
    }

    /// One chip. `tint == nil` is a neutral (muted) category; a non-nil tint
    /// colours both the count and a faint capsule wash. Hidden when count is 0.
    /// A non-nil `symbol` leads the count with the category's glyph — the two
    /// layout chips carry glyph + word + tint together, single-sourced from
    /// `OutputMode`, so the vocabulary can never drift from the controls'.
    @ViewBuilder
    private func chip(_ label: String, _ count: Int, _ tint: Color?,
                      symbol: String? = nil) -> some View {
        if count > 0 {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(tint ?? .secondary)
                }
                Text("\(count)")
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(tint ?? .secondary)
                Text(label)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((tint ?? .gray).opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Bottom apply bar

struct BottomBar: View {
    let model: AppModel
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SummaryChips(model: model)
            Spacer(minLength: 16)
            Text(statusNote).font(.callout).foregroundStyle(.secondary)
            Button(action: onApply) {
                Label("Apply renames", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasWork)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var hasWork: Bool {
        model.plan?.nodes.contains { $0.status == .rename } ?? false
    }

    private var statusNote: String {
        guard let plan = model.plan else { return "Choose a folder to begin." }
        let moves = plan.nodes.filter { $0.status == .rename }
            .reduce(0) { $0 + $1.previewPairs.count }
        let junk = model.junkToTrash.count
        if moves == 0 && junk == 0 { return "Nothing to apply." }
        return "\(count(moves, "file")) will move · \(count(junk, "junk file")) to Trash"
    }
}

// MARK: - Empty state

struct EmptyDetail: View {
    var message = "Select an item to preview."

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
