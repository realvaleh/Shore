import AppKit
import SwiftUI

@main
struct ShoreApp: App {
    @NSApplicationDelegateAdaptor(ShoreAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Shore", systemImage: "water.waves") {
            MenuBarContent()
                .environmentObject(ShoreSettings.shared)
        }

        Settings {
            SettingsView()
                .environmentObject(ShoreSettings.shared)
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var settings: ShoreSettings

    var body: some View {
        Toggle("Island", isOn: $settings.islandEnabled)
        Toggle("Dock Tide Line", isOn: $settings.dockEnabled)
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Shore") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
