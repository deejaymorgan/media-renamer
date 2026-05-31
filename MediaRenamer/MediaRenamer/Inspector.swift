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
                    TextField("Year", text: $year)
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
                    Text(node.mediaType == .tv ? "TV episode pack" : "Movie")
                        .font(.headline)
                    FlagBadges(node: node, conflicts: conflicts)
                    Spacer()
                }
                Text("from  \(node.originalName)")
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 6) {
                    EditFields(node: node, model: model).id(node.source)
                    Text("Title Case · hyphens preserved")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                if node.isConflicted(in: conflicts) {
                    ConflictNote(node: node)
                } else {
                    ResultingFiles(node: node)
                    if !node.junk.isEmpty { JunkList(node: node) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(node.destinationDirectory)
                        .fontWeight(.medium)
                        .lineLimit(1).truncationMode(.middle)
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
                    ConflictNote(node: node)
                } else {
                    ResultingFiles(node: node)
                    if !node.junk.isEmpty { JunkList(node: node) }
                }
            } else {
                Text("→ \(node.destinationDirectory) · \(node.previewPairs.count) file(s)")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Shared blocks

struct ResultingFiles: View {
    let node: NodePlan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resulting files").font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(node.previewPairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 1) {
                    Text(pair.new).font(.system(.body, design: .monospaced))
                    Text("← \(pair.old)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JunkList: View {
    let node: NodePlan
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Junk → Trash").font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(node.junk.enumerated()), id: \.offset) { _, url in
                HStack(spacing: 6) {
                    Image(systemName: "trash").foregroundStyle(.red)
                    Text(url.lastPathComponent)
                        .font(.system(.callout, design: .monospaced))
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConflictNote: View {
    let node: NodePlan
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Duplicate target", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.red)
            Text("Shares a destination with another file — both are skipped until disambiguated. Editing a title above can resolve it; the full resolve panel comes in a later step.")
                .font(.callout).foregroundStyle(.secondary)
            ResultingFiles(node: node)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
