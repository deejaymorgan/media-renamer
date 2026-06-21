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
            if !model.acronymWords.isEmpty {
                AcronymBar(model: model)
                Divider()
            }
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

            BottomBar(model: model) { confirming = true }
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
        .confirmationDialog("Apply renames?", isPresented: $confirming, titleVisibility: .visible) {
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
        return "\(url.path) · \(n) items"
    }

    private var applyPrompt: String {
        guard let plan = model.plan else { return "" }
        let moves = plan.nodes.filter { $0.status == .rename }
            .reduce(0) { $0 + $1.previewPairs.count }
        return "Move \(moves) files and send \(model.junkToTrash.count) junk to the Trash. "
            + "Renaming never overwrites; conflicted items are skipped."
    }
}

// MARK: - Summary chips (toolbar, trailing)

struct SummaryChips: View {
    let model: AppModel

    var body: some View {
        if let plan = model.plan {
            let g = PlanGroups(plan)
            HStack(spacing: 16) {
                chip("TV", g.tvRename.count, .blue)
                chip("Movies", g.movieRename.count, .purple)
                chip("Unchanged", g.unchanged.count, .secondary)
                chip("Skipped", g.skipped.count, .secondary)
                if !plan.conflicts.isEmpty { chip("Conflicts", plan.conflicts.count, .red) }
                if g.junkCount > 0 { chip("Junk", g.junkCount, .secondary) }
            }
            .padding(.trailing, 8)
        }
    }

    private func chip(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .bold()
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Bottom apply bar

struct BottomBar: View {
    let model: AppModel
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onApply) {
                Label("Apply renames", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasWork)

            Text(statusNote).font(.callout).foregroundStyle(.secondary)
            Spacer()
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
