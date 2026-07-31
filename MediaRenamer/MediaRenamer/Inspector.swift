import SwiftUI
import RenamerCore

struct DetailView: View {
    let model: AppModel

    var body: some View {
        if let plan = model.plan {
            switch model.selection {
            case .all?:
                AllModeView(plan: plan, model: model)
            case .item(let url)?:
                if let node = plan.nodes.first(where: { $0.source == url }) {
                    InspectorView(node: node, conflicts: plan.conflicts, model: model)
                } else {
                    EmptyDetail()
                }
            case let .season(show, number)?:
                if let node = plan.nodes.first(where: { $0.source == show }),
                   let slice = node.seasonSlice(number) {
                    SeasonInspectorView(node: node, slice: slice,
                                        conflicts: plan.conflicts, model: model)
                } else {
                    EmptyDetail()
                }
            case nil:
                EmptyDetail()
            }
        } else {
            EmptyDetail(message: "Choose a folder to preview the rename plan.")
        }
    }
}

// MARK: - Editable Title / Year

/// Title (and, for movies, Year) fields that re-plan the item live on each edit.
/// Local @State backs the fields; `.id(node.source)` gives each item fresh state.
struct EditFields: View {
    let node: NodePlan
    let model: AppModel
    @State private var title = ""
    @State private var year = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.mediaType == .tv ? "Show title" : "Movie title")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            if node.mediaType == .movie {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Year").font(.caption).foregroundStyle(.secondary)
                    TextField("Year", text: yearProxy)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                }
            }
        }
        .onAppear { title = node.editTitle; year = node.editYear }
        .onChange(of: title) { _, new in
            model.replan(itemSource: node.source, title: new, year: year)
        }
        .onChange(of: year) { _, new in
            model.replan(itemSource: node.source, title: title, year: new)
        }
    }

    /// Keeps the Year field to at most four digits as the user types, so a
    /// non-numeric or over-long year can't reach the rename plan. Clearing it is
    /// still allowed (an empty year drops the parenthetical in the engine).
    private var yearProxy: Binding<String> {
        Binding(get: { year },
                set: { year = String($0.filter(\.isNumber).prefix(4)) })
    }
}

/// In-context nudge under the title field, shown only when the engine made a
/// title-casing choice worth a glance — a preserved joined hyphen (`the-bear`
/// may have meant a space) or a kept source capital on a stopword (`Law And
/// Order` vs `Law and Order`). Each reason is its own actionable line, so the
/// flag is never unexplained. Renders nothing when there's nothing to verify.
struct TitleVerifyNote: View {
    let node: NodePlan
    var body: some View {
        if node.needsVerify {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(node.verifyReasons, id: \.self) { reason in
                    Label(reason, systemImage: "flag")
                        .font(.caption2).foregroundStyle(Palette.verify)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Single-item inspector

struct InspectorView: View {
    let node: NodePlan
    let conflicts: Set<URL>
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: node.mediaType == .tv ? "tv" : "film")
                        .foregroundStyle(.secondary)
                    Text(node.displayTitle).font(.headline)
                    // Reported, not set: layout is chosen from the sidebar row's
                    // context menu, or View ▸ Layout.
                    ModeBadge(mode: node.outputMode,
                              explicit: model.itemOverride(for: node.source) != .inherit)
                    FlagBadges(node: node, conflicts: conflicts)
                    Spacer()
                }
                Text(node.mediaType == .tv ? node.seasonSummary : "from  \(node.originalName)")
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 6) {
                    EditFields(node: node, model: model).id(node.source)
                    TitleVerifyNote(node: node)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                if node.isConflicted(in: conflicts) {
                    ConflictResolveSection(node: node, model: model)
                } else {
                    ResultingFiles(node: node, root: model.folderURL)
                    if !node.junk.isEmpty { JunkList(node: node, model: model) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Season focus

/// Focuses one season of a show: only that season's renames (or, if any of its
/// files collide, just those resolvers). The title field stays available —
/// editing it updates the whole show, not only this season.
struct SeasonInspectorView: View {
    let node: NodePlan
    let slice: SeasonSlice
    let conflicts: Set<URL>
    let model: AppModel

    private var conflictedHere: Bool { slice.sources.contains { conflicts.contains($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "tv").foregroundStyle(.secondary)
                    Text("\(node.displayTitle) · Season \(slice.number)").font(.headline)
                    ModeBadge(mode: node.outputMode,
                              explicit: model.itemOverride(for: node.source) != .inherit)
                    if conflictedHere {
                        Label("duplicate", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.iconOnly).foregroundStyle(Palette.conflict)
                    }
                    Spacer()
                }
                Text("\(slice.pairs.count) file\(slice.pairs.count == 1 ? "" : "s") in this season")
                    .font(.callout).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    EditFields(node: node, model: model).id(node.source)
                    // One override per show, never per season: flattening collapses
                    // every season into the same folder, so a per-season setting
                    // would change nothing visible. Layout is set from the show's
                    // sidebar row, which is the level it applies at.
                    Text("Editing the title updates every season of this show. "
                         + "To set its layout, right-click the show’s row in the "
                         + "sidebar, or use View ▸ Layout.")
                        .font(.caption2).foregroundStyle(.secondary)
                    TitleVerifyNote(node: node)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                if conflictedHere {
                    SeasonConflicts(node: node, slice: slice, model: model)
                } else {
                    SeasonResultingFiles(slice: slice, mode: node.outputMode,
                                         root: model.folderURL)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// This season's resulting files (already scoped to one season, so it renders a
/// single destination-folder band over the two-column table).
struct SeasonResultingFiles: View {
    let slice: SeasonSlice
    var mode: OutputMode = .organise
    var root: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resulting files").font(.subheadline).foregroundStyle(.secondary)
            FolderGroups(pairs: slice.pairs, mode: mode, root: root)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The duplicate resolvers for conflicts that involve this season's files.
struct SeasonConflicts: View {
    let node: NodePlan
    let slice: SeasonSlice
    let model: AppModel
    var body: some View {
        if let plan = model.plan {
            let here = node.displayConflicts(in: plan)
                .filter { c in c.group.contains { slice.sources.contains($0) } }
            ForEach(Array(here.enumerated()), id: \.offset) { _, c in
                ConflictResolveView(group: c.group, targetName: c.target, model: model)
                    .id(c.group.map(\.path).joined())
            }
        }
    }
}

// MARK: - All mode (collapsible cards, each editable)

struct AllModeView: View {
    let plan: Plan
    let model: AppModel
    @State private var expanded: Set<URL> = []

    private var items: [NodePlan] {
        plan.nodes.filter { $0.status == .rename }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("All items · \(items.count)").font(.headline)
                    Spacer()
                    Button("Expand all") { expanded = Set(items.map(\.source)) }
                    Button("Collapse all") { expanded = [] }
                }
                ForEach(items) { node in
                    AllCard(
                        node: node,
                        conflicts: plan.conflicts,
                        isExpanded: expanded.contains(node.source),
                        model: model
                    ) { toggle(node.source) }
                }
            }
            .padding(20)
        }
        .onAppear { expanded = Set(items.map(\.source)) }
    }

    private func toggle(_ url: URL) {
        if expanded.contains(url) { expanded.remove(url) } else { expanded.insert(url) }
    }
}

struct AllCard: View {
    let node: NodePlan
    let conflicts: Set<URL>
    let isExpanded: Bool
    let model: AppModel
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                    Image(systemName: node.mediaType == .tv ? "tv" : "film")
                        .foregroundStyle(.secondary)
                    Text(node.displayTitle)
                        .fontWeight(.medium)
                        .lineLimit(1).truncationMode(.tail)
                        .help(node.displayTitle)
                    Spacer()
                    ModeBadge(mode: node.outputMode,
                              explicit: model.itemOverride(for: node.source) != .inherit)
                    // Not compact: this is a ~630pt card, not a 218pt row, and
                    // the ModeBadge beside it spells its mode out in full.
                    FlagBadges(node: node, conflicts: conflicts)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Always-editable fields (don't toggle the card). Layout is not among
            // them: it is set from the sidebar row's context menu (or View ▸
            // Layout), and this badge reports it.
            EditFields(node: node, model: model).id(node.source)

            if isExpanded {
                if node.isConflicted(in: conflicts) {
                    ConflictResolveSection(node: node, model: model)
                } else {
                    ResultingFiles(node: node, root: model.folderURL)
                    if !node.junk.isEmpty { JunkList(node: node, model: model) }
                }
            } else {
                (Text("→ ").foregroundStyle(.secondary)
                 + Text(node.displayTitle).foregroundStyle(Palette.renamed)
                 + Text(" · \(node.seasonSummary)").foregroundStyle(.secondary))
                    .font(.callout)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Shared blocks

/// Presentation helpers that split a before→after pair into the parts the
/// resulting-files table shows separately: the destination folder (hoisted into
/// a header band) and the bare filename (shown in a row), so the repeated
/// `Show/Season N/` prefix appears once instead of on every line.
private extension PreviewPair {
    /// Slash-separated components of the destination (root-relative) path.
    var newParts: [Substring] { new.split(separator: "/") }
    /// Destination folder as a breadcrumb, e.g. "The Bear › Season 1"; "" when
    /// the file lands at the root with no enclosing folder.
    var destFolder: String { newParts.dropLast().joined(separator: " › ") }
    /// Just the resulting filename.
    var newFilename: String { String(newParts.last ?? Substring(new)) }
    /// Just the original filename (any scene folder it sat in is dropped — the
    /// full original path stays available as a tooltip on the row).
    var oldFilename: String { String(old.split(separator: "/").last ?? Substring(old)) }
    /// Row glyph: a caption bubble for subtitle sidecars, else a film cell.
    var kindSymbol: String {
        let ext = "." + (newFilename as NSString).pathExtension.lowercased()
        return Constants.subtitleExtensions.contains(ext) ? "captions.bubble" : "film"
    }
}

/// Groups pairs by their destination folder, preserving first-seen order.
private func groupedByFolder(_ pairs: [PreviewPair]) -> [(folder: String, pairs: [PreviewPair])] {
    var order: [String] = []
    var byFolder: [String: [PreviewPair]] = [:]
    for pair in pairs {
        if byFolder[pair.destFolder] == nil { order.append(pair.destFolder) }
        byFolder[pair.destFolder, default: []].append(pair)
    }
    return order.map { ($0, byFolder[$0]!) }
}

/// A tinted breadcrumb band marking the destination folder a group lands in.
/// Folders read distinctly from the files beneath them: a filled folder glyph,
/// a quaternary fill, and the show/season crumbs joined by a muted "›".
///
/// A flat group keeps the same band — same fill, same shape — and differs by its
/// glyph, its tint, and naming the folder the files land in. Dropping the band
/// for flat items would make a mixed plan unreadable: every group has to state
/// where it lands, or a flat group and an organised one look identical.
///
/// It used to carry a muted "flattened" tag as well. That was a third vocabulary
/// for a distinction the glyph and tint already draw, and the word appeared
/// nowhere else in the app.
/// **Every band starts at the chosen folder.** Organised groups read
/// `downloads › Silo › Season 3`, flat groups read `downloads` — the two shapes
/// are structurally parallel, and both answer "which folder?", which is the
/// question that was actually going unanswered: organised bands used to name
/// the show and the season but never the root they hung off, so with the same
/// file present in two folders on disk the preview couldn't say which one it
/// had scanned. The leading crumb is context rather than content, so it is
/// de-emphasised — unless it is the whole answer, which is the flat case.
private struct FolderBand: View {
    /// Path components from the chosen folder down, the chosen folder first.
    let crumbs: [String]
    /// The folder those crumbs name. Usually does not exist yet — the tree is
    /// built at Apply — but the path is real either way.
    let url: URL?
    var mode: OutputMode = .organise

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode.bandSymbol)
                .foregroundStyle(mode.tint)
            crumbText
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .help(helpText)
        .contextMenu {
            if let url {
                Button("Reveal in Finder") {
                    if let target = revealTarget {
                        NSWorkspace.shared.activateFileViewerSelecting([target])
                    }
                }
                .disabled(revealTarget == nil)
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        }
    }

    /// The full destination path — the band names a folder, the tooltip says
    /// exactly which one.
    private var helpText: String {
        let path = url?.path ?? crumbs.joined(separator: "/")
        return mode == .renameOnly
            ? "Flat — these files land directly in \(path), with no folder tree."
            : "These files land in \(path)."
    }

    /// The deepest part of the destination that exists right now. An organised
    /// group's folder is usually not built until Apply, so revealing it verbatim
    /// would silently do nothing; walking up lands the user in the chosen folder
    /// instead, which is the useful answer.
    private var revealTarget: URL? {
        guard var target = url else { return nil }
        while !FileManager.default.fileExists(atPath: target.path) {
            let parent = target.deletingLastPathComponent()
            guard parent.path != target.path else { return nil }
            target = parent
        }
        return target
    }

    private var crumbText: Text {
        crumbs.enumerated().reduce(Text("")) { acc, part in
            let sep = part.offset == 0 ? Text("") : Text(" › ").foregroundStyle(.tertiary)
            let leadingRoot = part.offset == 0 && crumbs.count > 1
            let crumb = leadingRoot
                ? Text(part.element).foregroundStyle(.secondary)
                : Text(part.element).foregroundStyle(.primary)
            return acc + sep + crumb
        }
    }
}

/// One before→after row: a file-kind glyph, the original filename (muted) on the
/// left, an arrow, and the resulting filename (green) on the right. The two name
/// columns split the row evenly so they line up into a table across rows.
struct PairRow: View {
    let pair: PreviewPair
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pair.kindSymbol)
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 16)
            Text(pair.oldFilename)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(pair.old)
            Image(systemName: "arrow.right")
                .font(.caption).foregroundStyle(.tertiary)
            Text(pair.newFilename)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Palette.renamed)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(pair.new)
        }
    }
}

/// One destination folder: its breadcrumb band over the two-column table of the
/// files that land in it.
private struct FolderGroup: View {
    /// Destination folder relative to the root, as " › "-joined crumbs. Empty
    /// when the files land in the root itself — which is the flat case, and no
    /// longer needs a branch of its own: a flat band is the one-crumb form of
    /// the same band, not a different band.
    let folder: String
    let pairs: [PreviewPair]
    var mode: OutputMode = .organise
    var root: URL?

    private var subfolders: [String] {
        folder.isEmpty ? [] : folder.components(separatedBy: " › ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FolderBand(crumbs: [root?.lastPathComponent ?? "the chosen folder"] + subfolders,
                       url: subfolders.reduce(root) { $0?.appendingPathComponent($1) },
                       mode: mode)
            // Indent the files under their folder band, with a guide rail, so
            // each list reads as nested inside its destination folder.
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.tertiary)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                        PairRow(pair: pair)
                    }
                }
            }
            .padding(.leading, 16)
        }
    }
}

/// Renders each destination folder in `pairs` as its own `FolderGroup`.
struct FolderGroups: View {
    let pairs: [PreviewPair]
    var mode: OutputMode = .organise
    var root: URL?

    var body: some View {
        ForEach(Array(groupedByFolder(pairs).enumerated()), id: \.offset) { _, group in
            FolderGroup(folder: group.folder, pairs: group.pairs,
                        mode: mode, root: root)
        }
    }
}

struct ResultingFiles: View {
    let node: NodePlan
    var root: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resulting files").font(.subheadline).foregroundStyle(.secondary)
            // Organised TV iterates seasons in ascending order (each becomes its
            // own band); movies fall through to a single group. A flat show takes
            // that same single-group path on purpose: every season lands in the
            // one folder, so per-season bands would repeat one destination.
            if node.outputMode == .organise, node.mediaType == .tv, !node.seasonSlices.isEmpty {
                ForEach(node.seasonSlices) { slice in
                    FolderGroups(pairs: slice.pairs, root: root)
                }
            } else {
                FolderGroups(pairs: node.previewPairs,
                             mode: node.outputMode, root: root)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JunkList: View {
    let node: NodePlan
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Junk → Trash").font(.subheadline).foregroundStyle(.secondary)
            ForEach(node.junk, id: \.self) { url in
                Toggle(isOn: Binding(
                    get: { model.isJunkTrashed(url) },
                    set: { model.setJunkTrashed(url, $0) }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").foregroundStyle(Palette.junk)
                        Text(url.lastPathComponent)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Duplicate-conflict resolver

/// Renders one resolver per distinct conflict group the node participates in
/// (almost always exactly one).
struct ConflictResolveSection: View {
    let node: NodePlan
    let model: AppModel

    var body: some View {
        if let plan = model.plan {
            ForEach(Array(node.displayConflicts(in: plan).enumerated()), id: \.offset) { _, c in
                ConflictResolveView(group: c.group, targetName: c.target, model: model)
                    .id(c.group.map(\.path).joined())
            }
        }
    }
}

/// Lets the user keep every file in a duplicate group by giving each a version
/// label. Fields are pre-filled from each filename's parsed quality
/// (auto-tag); editing a field is the rename-to path; Skip leaves them all.
struct ConflictResolveView: View {
    let group: [URL]
    let targetName: String
    let model: AppModel
    @State private var labels: [URL: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Duplicate target", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Palette.conflict)
            Text("\(group.count) files want the same name. Give each a version label to keep them all — they’ll share one folder, the way Plex and Jellyfin expect.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(group, id: \.self) { src in
                VStack(alignment: .leading, spacing: 3) {
                    Text(src.lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        TextField("Version label", text: label(for: src))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Text("→ \(resultName(for: src))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Palette.renamed)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }

            if !canResolve {
                Label("Give every file a different, non-empty label.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button("Resolve") { model.resolve(labels) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canResolve)
                Button("Skip (leave all)") { model.skipConflict(group) }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.conflict.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { if labels.isEmpty { labels = QualityTag.distinctLabels(for: group) } }
    }

    private func label(for src: URL) -> Binding<String> {
        Binding(get: { labels[src] ?? "" }, set: { labels[src] = $0 })
    }

    /// The destination filename with this file's label spliced in before the
    /// extension — a live preview of what "Resolve" will produce. The label is
    /// sanitised exactly as the engine does (`PlanBuilder.sanitizeSeparators`),
    /// so the preview matches the name that actually lands on disk.
    private func resultName(for src: URL) -> String {
        let lbl = PlanBuilder.sanitizeSeparators(labels[src] ?? "")
        guard !lbl.isEmpty else { return targetName }
        let ns = targetName as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        return ext.isEmpty ? "\(base) - \(lbl)" : "\(base) - \(lbl).\(ext)"
    }

    /// Every file needs a non-empty label, and no two may match.
    private var canResolve: Bool {
        let trimmed = group.map { (labels[$0] ?? "").trimmingCharacters(in: .whitespaces) }
        return !trimmed.contains("") && Set(trimmed).count == trimmed.count
    }
}

