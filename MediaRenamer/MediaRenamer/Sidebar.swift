import SwiftUI
import RenamerCore

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            if let plan = model.plan {
                let g = PlanGroups(plan)

                AllItemsRow(count: g.tvRename.count + g.movieRename.count)
                    .tag(Selection.all)

                if !g.tvRename.isEmpty {
                    Section("TV") {
                        ForEach(g.tvRename) { show in
                            ShowRow(node: show, conflicts: plan.conflicts,
                                    expanded: model.isShowExpanded(show.source),
                                    canExpand: show.isMultiSeason,
                                    toggle: { model.toggleShow(show.source) })
                                .tag(Selection.item(show.source))

                            if show.isMultiSeason, model.isShowExpanded(show.source) {
                                ForEach(show.seasonSlices) { slice in
                                    SeasonRow(slice: slice, conflicts: plan.conflicts)
                                        .tag(Selection.season(show: show.source, number: slice.number))
                                }
                            }
                        }
                    }
                }
                if !g.movieRename.isEmpty {
                    Section("Movies") {
                        ForEach(g.movieRename) { node in
                            SidebarRow(node: node, conflicts: plan.conflicts)
                                .tag(Selection.item(node.source))
                        }
                    }
                }
                if !g.unchanged.isEmpty {
                    Section("Unchanged") {
                        ForEach(g.unchanged) { node in
                            MutedRow(name: node.originalName, detail: "already named")
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

/// A TV show row: a disclosure chevron (when the show spans multiple seasons),
/// the show name, and a season/file summary. Selecting it focuses the whole show
/// — every season's files, one title edit for all.
struct ShowRow: View {
    let node: NodePlan
    let conflicts: Set<URL>
    let expanded: Bool
    let canExpand: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .opacity(canExpand ? 1 : 0)
            .disabled(!canExpand)

            Image(systemName: "tv").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.displayTitle)
                    .lineLimit(1).truncationMode(.middle)
                Text(node.seasonSummary)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            FlagBadges(node: node, conflicts: conflicts, compact: true)
        }
        .padding(.vertical, 2)
    }
}

/// An indented season row under a show. Selecting it focuses just that season.
struct SeasonRow: View {
    let slice: SeasonSlice
    let conflicts: Set<URL>

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
                    .font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 1)
    }
}

struct AllItemsRow: View {
    let count: Int
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
        }
        .padding(.vertical, 2)
    }
}

struct SidebarRow: View {
    let node: NodePlan
    let conflicts: Set<URL>
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.mediaType == .tv ? "tv" : "film")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.destinationDirectory)
                    .lineLimit(1).truncationMode(.middle)
                Text(node.originalName)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            FlagBadges(node: node, conflicts: conflicts, compact: true)
        }
        .padding(.vertical, 2)
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
                badge(compact ? "dup" : "duplicate", "exclamationmark.triangle.fill", .red)
            }
            if !node.junk.isEmpty {
                badge("\(node.junk.count) junk", "trash", .red)
            }
            if !node.verifyTitle.isEmpty {
                badge(compact ? nil : "verify", "flag", .orange)
            }
        }
    }

    private func badge(_ text: String?, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if let text { Text(text) }
        }
        .font(.caption2)
        .foregroundStyle(color)
    }
}
