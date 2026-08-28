import SwiftUI

@main
struct NekoBoxApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 620)
        }
        .commands {
            AppCommands(state: state)
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

private struct AppCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Reload Profiles") {
                state.reloadLegacyData()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu("Connection") {
            Button("Connect Selected Proxy") {
                state.startSelectedProfile()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Disconnect") {
                state.stopCore()
            }
            .keyboardShortcut(".", modifiers: [.command])
        }
    }
}
