import SwiftUI
import UniformTypeIdentifiers
import RenamerCore

struct ContentView: View {
    // @State owns the @Observable model for this view's lifetime.
    @State private var model = AppModel()
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                model.choose(url)
            }
        }
    }

    // MARK: Top bar

    private var sourceBar: some View {
        HStack(spacing: 10) {
            Button {
                importing = true
            } label: {
                Label("Choose Folder…", systemImage: "folder")
            }
            Text(model.folderURL?.path ?? "No folder chosen")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(10)
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        if let plan = model.plan {
            SummaryBar(plan: plan)
            Divider()
            PlanList(plan: plan)
        } else {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Choose a folder to preview the rename plan.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var footer: some View {
        Text("Read-only preview — no files are changed yet.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

// MARK: - Grouping

/// Splits a plan's nodes into the display buckets (same grouping the CLI uses).
private struct PlanGroups {
    let tv: [NodePlan]
    let movies: [NodePlan]
    let unchanged: [NodePlan]
    let skipped: [NodePlan]
    let verify: [NodePlan]
    let junkCount: Int

    init(_ plan: Plan) {
        tv = plan.nodes.filter { $0.mediaType == .tv && $0.status == .rename }
        movies = plan.nodes.filter { $0.mediaType == .movie && $0.status == .rename }
        unchanged = plan.nodes.filter { $0.status == .unchanged }
        skipped = plan.nodes.filter { $0.status == .skip }
        verify = plan.nodes.filter { !$0.verifyTitle.isEmpty }
        junkCount = plan.nodes.reduce(0) { $0 + $1.junk.count }
    }
}

// MARK: - Summary

private struct SummaryBar: View {
    let plan: Plan

    var body: some View {
        let g = PlanGroups(plan)
        HStack(spacing: 16) {
            chip("TV", g.tv.count, .blue)
            chip("Movies", g.movies.count, .purple)
            chip("Unchanged", g.unchanged.count, .secondary)
            chip("Skipped", g.skipped.count, .secondary)
            if !g.verify.isEmpty { chip("Verify", g.verify.count, .orange) }
            if !plan.conflicts.isEmpty { chip("Conflicts", plan.conflicts.count, .red) }
            if g.junkCount > 0 { chip("Junk", g.junkCount, .secondary) }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func chip(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").bold().foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Plan list

private struct PlanList: View {
    let plan: Plan

    var body: some View {
        let g = PlanGroups(plan)
        List {
            renameSection("TV", g.tv, color: .blue)
            renameSection("Movies", g.movies, color: .purple)
            simpleSection("Unchanged", g.unchanged, note: { _ in "" })
            simpleSection("Skipped", g.skipped, note: { $0.note })
            if !g.verify.isEmpty {
                Section {
                    ForEach(g.verify) { node in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(node.verifyTitle)
                            Text(node.verifyWords.map { "'\($0)'" }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Titles to verify (\(g.verify.count))")
                }
            }
        }
    }

    @ViewBuilder
    private func renameSection(_ title: String, _ nodes: [NodePlan], color: Color) -> some View {
        if !nodes.isEmpty {
            Section {
                ForEach(nodes) { node in
                    VStack(alignment: .leading, spacing: 3) {
                        if isConflicted(node) {
                            Label("Duplicate target — will be skipped",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        ForEach(Array(node.previewPairs.enumerated()), id: \.offset) { _, pair in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pair.old).foregroundStyle(.secondary)
                                Text("→ \(pair.new)").foregroundStyle(color)
                            }
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                }
            } header: {
                Text("\(title) (\(nodes.count))")
            }
        }
    }

    @ViewBuilder
    private func simpleSection(
        _ title: String, _ nodes: [NodePlan], note: @escaping (NodePlan) -> String
    ) -> some View {
        if !nodes.isEmpty {
            Section {
                ForEach(nodes) { node in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.source.lastPathComponent)
                        let text = note(node)
                        if !text.isEmpty {
                            Text(text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("\(title) (\(nodes.count))")
            }
        }
    }

    /// A node is conflicted if any of its moves targets a duplicate destination.
    /// (The whole node is skipped at apply time, so we flag it as a unit.)
    private func isConflicted(_ node: NodePlan) -> Bool {
        node.operations.contains { op in
            if case let .move(from, _) = op { return plan.conflicts.contains(from) }
            return false
        }
    }
}

#Preview {
    ContentView()
}
