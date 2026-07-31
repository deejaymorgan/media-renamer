//
//  MediaRenamerApp.swift
//  MediaRenamer
//
//  Created by Daniel Morgan on 30/5/2026.
//

import SwiftUI

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

/// Reset-all as a menu command as well as a toolbar button — the toolbar
/// indicator only appears once there is something to reset, so the menu is
/// where you look for it if you are not sure whether there is.
struct LayoutCommands: Commands {
    @FocusedValue(\.appModel) private var model

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Reset All Layout Overrides") { model?.resetAllOverrides() }
                .disabled((model?.overrideCount ?? 0) == 0)
        }
    }
}
