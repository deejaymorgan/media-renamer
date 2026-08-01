//
//  MediaRenamerApp.swift
//  MediaRenamer
//
//  Created by Daniel Morgan on 30/5/2026.
//

import SwiftUI
import RenamerCore

@main
struct MediaRenamerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands { LayoutCommands() }
    }
}

/// Carries the focused window's model out to the menu bar. Commands live
/// outside the view hierarchy, so they cannot reach `ContentView`'s state any
/// other way.
struct AppModelKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var appModel: AppModel? {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}

/// The layout commands in the menu bar: set the selected item's layout, and
/// reset every override.
///
/// `Layout ▸` is the required mirror of the sidebar row's context menu — the HIG
/// asks that every context-menu command also be reachable from the main
/// interface, and that mirror is what makes right-click a legitimate primary
/// home for the item rung rather than a hiding place. Reset-all is here for the
/// opposite reason: the toolbar indicator only appears once there is something
/// to reset, so the menu is where you look if you are not sure whether there is.
struct LayoutCommands: Commands {
    @FocusedValue(\.appModel) private var model

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            layoutMenu
            groupMenus
            Button("Reset All Layout Overrides") { model?.resetAllOverrides() }
                .disabled((model?.overrideCount ?? 0) == 0)
        }
    }

    /// The group rung's menu-bar home, one menu per media kind. The header
    /// chips remain the in-context setters; these are their required mirrors —
    /// added 2026-08-01, when it was noticed the rung had none, which
    /// contradicted the mirror rule the item rung above is explicitly built
    /// on. Disabled — but present — before a folder is chosen, for the same
    /// reason `layoutMenu` is: discoverable before applicable.
    @ViewBuilder
    private var groupMenus: some View {
        if let model, model.plan != nil {
            Menu("Layout — TV") {
                LayoutPicker(
                    current: model.groupOverride(for: .tv),
                    inherited: model.globalMode,
                    set: { model.setGroupOverride($0, for: .tv) }
                )
            }
            Menu("Layout — Movies") {
                LayoutPicker(
                    current: model.groupOverride(for: .movie),
                    inherited: model.globalMode,
                    set: { model.setGroupOverride($0, for: .movie) }
                )
            }
        } else {
            Button("Layout — TV") { }.disabled(true)
            Button("Layout — Movies") { }.disabled(true)
        }
    }

    /// Named with the item it targets, deliberately. A right-click does not move
    /// `List` selection, so the row menu and this one can point at different
    /// rows at the same moment; saying whose layout this is stops that being
    /// silent. Disabled — but present — for "All items" and for no selection, so
    /// the command is discoverable before it is applicable.
    @ViewBuilder
    private var layoutMenu: some View {
        if let model, let node = model.selectedLayoutTarget {
            Menu("Layout — “\(node.displayTitle)”") {
                LayoutPicker(
                    current: model.itemOverride(for: node.source),
                    inherited: model.inheritedMode(for: node),
                    set: { model.setItemOverride($0, for: node.source) }
                )
            }
        } else {
            Button("Layout") { }.disabled(true)
        }
    }
}
