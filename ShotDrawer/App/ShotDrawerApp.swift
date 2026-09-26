import SwiftUI

@main
struct ShotDrawerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1_120, height: 720)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label(appState.menuBarLabel, systemImage: "rectangle.stack")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520)
        }
    }
}
