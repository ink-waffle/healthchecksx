import AppKit
import SwiftUI

extension View {
    /// Keeps the app in the Dock for as long as this view's window is open.
    func keepsAppInDock() -> some View {
        onAppear { DockPresence.openWindows += 1 }
            .onDisappear { DockPresence.openWindows -= 1 }
    }
}

/// The app sits in the Dock, and comes forward, only while at least one of its windows is open.
private enum DockPresence {
    static var openWindows = 0 {
        didSet {
            NSApplication.shared.setActivationPolicy(openWindows > 0 ? .regular : .accessory)
            if openWindows > 0 { NSApplication.shared.activate() }
        }
    }
}
