import SwiftUI

@main
struct SituationSimApp: App {
    #if os(macOS)
    init() {
        AppUpdater.shared.start()
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                    .disabled(!AppUpdater.shared.canCheck)
            }
        }

        Settings {
            SettingsView()
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
