import SwiftUI

/// Global keep|Title decisions for all-caps words, applied everywhere a word
/// appears. Shown under the toolbar only when such words are present; toggling
/// a chip re-plans the whole folder live.
struct AcronymBar: View {
    let model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                Label("Acronyms", systemImage: "textformat")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.acronymWords, id: \.self) { word in
                    AcronymChip(word: word, model: model)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}

struct AcronymChip: View {
    let word: String
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            Picker("", selection: binding) {
                Text("keep").tag(AcronymMode.keep)
                Text("Title").tag(AcronymMode.title)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text(readout)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var binding: Binding<AcronymMode> {
        Binding(get: { model.mode(for: word) },
                set: { model.setMode($0, for: word) })
    }

    private var readout: String {
        model.mode(for: word) == .keep ? "keeps \(word)" : "→ \(titleCased(word))"
    }

    private func titleCased(_ w: String) -> String {
        guard let f = w.first else { return w }
        return f.uppercased() + w.dropFirst().lowercased()
    }
}
