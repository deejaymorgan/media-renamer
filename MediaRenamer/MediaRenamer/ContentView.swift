import SwiftUI
import UniformTypeIdentifiers
import RenamerCore

struct ContentView: View {
    @State private var model = AppModel()
    @State private var importing = false
    @State private var confirming = false
    @State private var showResult = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(model: model)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300)
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
                    // places are ignoring this."
                    ToolbarItem(placement: .primaryAction) {
                        OverridesIndicator(model: model)
                    }
                }
            }

            // Acronym controls sit just above the apply bar, shown only when
            // there are all-caps words to decide. A bottom sibling avoids the
            // macOS 26 split-view safe-area bug that forced the old title-bar
            // accessory (see AcronymTitlebar, now unused).
            if !model.acronymWords.isEmpty {
                Divider()
                AcronymBar(model: model)
            }
            Divider()
            BottomBar(model: model) { confirming = true }
        }
        .frame(minWidth: 960, minHeight: 640)
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
struct OverridesIndicator: View {
    let model: AppModel

    var body: some View {
        if model.overrideCount > 0 {
            HStack(spacing: 4) {
                Text(count(model.overrideCount, "override"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    model.resetAllOverrides()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reset all layout overrides")
            }
            .help("\(count(model.overrideCount, "layout override")) in force. "
                  + "Reset returns every TV, Movies and row setting to inheriting.")
        }
    }
}

// MARK: - Summary chips (bottom bar, leading)

/// The per-category plan breakdown, rendered as colour-coded chips at the
/// leading edge of the bottom bar (Apply and the status note sit trailing). Only
/// non-empty categories show, so the row stays tight on small folders.
struct SummaryChips: View {
    let model: AppModel

    var body: some View {
        if let plan = model.plan {
            let g = PlanGroups(plan)
            HStack(spacing: 8) {
                chip("TV", g.tvRename.count, Palette.tv)
                chip("Movies", g.movieRename.count, Palette.movie)
                chip("Unchanged", g.unchanged.count, nil)
                chip("Skipped", g.skipped.count, nil)
                chip("Conflicts", plan.conflicts.count, Palette.conflict)
                chip("Junk", g.junkCount, Palette.junk)
            }
        }
    }

    /// One chip. `tint == nil` is a neutral (muted) category; a non-nil tint
    /// colours both the count and a faint capsule wash. Hidden when count is 0.
    @ViewBuilder
    private func chip(_ label: String, _ count: Int, _ tint: Color?) -> some View {
        if count > 0 {
            HStack(spacing: 4) {
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
