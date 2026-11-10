import SwiftUI

@main
struct HealthchecksXApp: App {
    @State private var store: ChecksStore

    init() {
        // Tooltips carry the full failure reasons, so they appear after a second instead of the system's longer default.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 1000])
        let store = ChecksStore()
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .keepsAppInDock()
        }
    }
}
