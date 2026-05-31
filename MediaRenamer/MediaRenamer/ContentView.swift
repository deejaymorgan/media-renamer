import SwiftUI
import UniformTypeIdentifiers
import RenamerCore

struct ContentView: View {
    @State private var model = AppModel()
    @State private var importing = false

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
                ToolbarItemGroup(placement: .primaryAction) {
                    SummaryChips(model: model)
                }
            }

            BottomBar(model: model)
        }
        .frame(minWidth: 960, minHeight: 640)
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

    private var subtitle: String {
        guard let plan = model.plan, let url = model.folderURL else {
            return "No folder chosen"
        }
        let n = plan.nodes.filter { $0.status == .rename }.count
        return "\(url.path) · \(n) items"
    }
}

// MARK: - Summary chips (toolbar, trailing)

struct SummaryChips: View {
    let model: AppModel

    var body: some View {
        if let plan = model.plan {
            let g = PlanGroups(plan)
            HStack(spacing: 12) {
                chip("TV", g.tvRename.count, .blue)
                chip("Movies", g.movieRename.count, .purple)
                chip("Unchanged", g.unchanged.count, .secondary)
                chip("Skipped", g.skipped.count, .secondary)
                if !plan.conflicts.isEmpty { chip("Conflicts", plan.conflicts.count, .red) }
                if g.junkCount > 0 { chip("Junk", g.junkCount, .secondary) }
            }
        }
    }

    private func chip(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)").bold().foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Bottom apply bar

struct BottomBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Button { } label: {
                Label("Apply renames", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)   // wired up in a later step

            Text(statusNote).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text("Read-only preview").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var statusNote: String {
        guard let plan = model.plan else { return "Choose a folder to begin." }
        let moves = plan.nodes
            .filter { $0.status == .rename }
            .reduce(0) { $0 + $1.previewPairs.count }
        let junk = plan.nodes.reduce(0) { $0 + $1.junk.count }
        return "\(moves) files will move · \(junk) junk to Trash"
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
