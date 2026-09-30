import SwiftUI

@main
struct SituationSimApp: App {
    #if os(macOS)
    init() {
        AppUpdater.shared.start()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 1000, minHeight: 680)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                    .disabled(!AppUpdater.shared.canCheck)
            }
        }
        #endif
    }
}
