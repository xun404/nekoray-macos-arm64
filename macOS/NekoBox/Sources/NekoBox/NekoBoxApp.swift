import SwiftUI

@main
struct NekoBoxApp: App {
    @StateObject private var state = AppState()
    @AppStorage("language") private var languageID = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageID) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environment(\.locale, language.locale)
                .frame(minWidth: 900, minHeight: 620)
        }
        .commands {
            AppCommands(state: state)
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environment(\.locale, language.locale)
        }
    }
}

private struct AppCommands: Commands {
    @ObservedObject var state: AppState
    @AppStorage("language") private var languageID = AppLanguage.english.rawValue

    var body: some Commands {
        let _ = languageID
        CommandGroup(replacing: .newItem) {
            Button(L10n.text("commands.reloadProfiles")) {
                state.reloadLegacyData()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu(L10n.text("commands.connection")) {
            Button(L10n.text("commands.connectSelectedProxy")) {
                state.startSelectedProfile()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(L10n.text("common.disconnect")) {
                state.stopCore()
            }
            .keyboardShortcut(".", modifiers: [.command])
        }
    }
}
