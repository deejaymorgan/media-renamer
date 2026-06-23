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
                    FlagBadges(node: node, conflicts: conflicts)
                    Spacer()
                }
                Text(node.mediaType == .tv ? node.seasonSummary : "from  \(node.originalName)")
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 6) {
                    EditFields(node: node, model: model).id(node.source)
                    Text(node.mediaType == .tv
                         ? "Title Case · hyphens preserved · applies to every season"
                         : "Title Case · hyphens preserved")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                if node.isConflicted(in: conflicts) {
                    ConflictResolveSection(node: node, model: model)
                } else {
                    ResultingFiles(node: node)
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
                    Text("Editing the title updates every season of this show.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                if conflictedHere {
                    SeasonConflicts(node: node, slice: slice, model: model)
                } else {
                    SeasonResultingFiles(slice: slice)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resulting files").font(.subheadline).foregroundStyle(.secondary)
            FolderGroups(pairs: slice.pairs)
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
            VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 8) {
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
                    FlagBadges(node: node, conflicts: conflicts, compact: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Always-editable fields (don't toggle the card).
            EditFields(node: node, model: model).id(node.source)

            if isExpanded {
                if node.isConflicted(in: conflicts) {
                    ConflictResolveSection(node: node, model: model)
                } else {
                    ResultingFiles(node: node)
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
        .padding(12)
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
private struct FolderBand: View {
    let crumb: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").foregroundStyle(.blue)
            crumbText
        }
        .font(.callout)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private var crumbText: Text {
        crumb.components(separatedBy: " › ").enumerated().reduce(Text("")) { acc, part in
            let sep = part.offset == 0 ? Text("") : Text(" › ").foregroundStyle(.tertiary)
            return acc + sep + Text(part.element).foregroundStyle(.primary)
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
    let folder: String
    let pairs: [PreviewPair]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !folder.isEmpty { FolderBand(crumb: folder) }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    PairRow(pair: pair)
                }
            }
            .padding(.leading, 6)
        }
    }
}

/// Renders each destination folder in `pairs` as its own `FolderGroup`.
struct FolderGroups: View {
    let pairs: [PreviewPair]
    var body: some View {
        ForEach(Array(groupedByFolder(pairs).enumerated()), id: \.offset) { _, group in
            FolderGroup(folder: group.folder, pairs: group.pairs)
        }
    }
}

struct ResultingFiles: View {
    let node: NodePlan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resulting files").font(.subheadline).foregroundStyle(.secondary)
            // TV iterates seasons in ascending order (each becomes its own band);
            // movies fall through to a single flat group.
            if node.mediaType == .tv, !node.seasonSlices.isEmpty {
                ForEach(node.seasonSlices) { slice in
                    FolderGroups(pairs: slice.pairs)
                }
            } else {
                FolderGroups(pairs: node.previewPairs)
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

