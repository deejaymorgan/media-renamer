import SwiftUI
import AppKit

/// Hosts the acronym bar as a window **title-bar accessory** (a full-width strip
/// directly below the toolbar) instead of a SwiftUI sibling above the
/// `NavigationSplitView`.
///
/// Why not a plain sibling bar: on macOS 26 the split view joins the unified
/// title bar and mis-propagates the toolbar height into the detail column's top
/// safe area (rdar://122947424). A sibling material bar above the split view then
/// gets underlapped by the detail's scroll content on the *first* layout pass —
/// the inspector's first row renders under the bar's material and looks blurred,
/// clearing only after a window resize forces a geometry re-resolution. Folding
/// the bar into the split view's safe area with `.safeAreaInset` doesn't help
/// (the same bug double-counts the inset and clips the row instead).
///
/// A genuine `NSTitlebarAccessoryViewController` sidesteps the SwiftUI bug
/// entirely: it's real window chrome, so AppKit reserves its space and computes
/// the content safe area correctly. The detail title clears the bar on the very
/// first layout, with spacing that matches the rest of the chrome — no blur, no
/// resize, no magic constant. The accessory is added/removed as acronym words
/// come and go, and its SwiftUI content stays live against the shared model.
struct AcronymTitlebar: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let reader = WindowReaderView()
        reader.onWindowChange = { [coordinator = context.coordinator] window in
            coordinator.attach(to: window)
        }
        return reader
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(showing: !model.acronymWords.isEmpty)
    }

    final class Coordinator {
        private let model: AppModel
        private let accessory = NSTitlebarAccessoryViewController()
        private weak var window: NSWindow?
        private var installed = false

        init(model: AppModel) {
            self.model = model
            accessory.layoutAttribute = .bottom
            let host = NSHostingView(rootView: AcronymBar(model: model))
            host.frame = NSRect(x: 0, y: 0, width: 800, height: Self.barHeight)
            host.autoresizingMask = [.width]
            accessory.view = host
        }

        /// Called whenever the backing view enters/leaves a window.
        func attach(to window: NSWindow?) {
            self.window = window
            update(showing: !model.acronymWords.isEmpty)
        }

        /// Add or remove the accessory to match whether any acronyms are present.
        func update(showing: Bool) {
            guard let window else { return }
            if showing, !installed {
                window.addTitlebarAccessoryViewController(accessory)
                installed = true
            } else if !showing, installed {
                if let idx = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
                    window.removeTitlebarAccessoryViewController(at: idx)
                }
                installed = false
            }
        }

        private static let barHeight: CGFloat = 34
    }
}

/// A zero-footprint `NSView` that reports when it joins (or leaves) a window, so
/// the coordinator can install the title-bar accessory at the right moment.
final class WindowReaderView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
