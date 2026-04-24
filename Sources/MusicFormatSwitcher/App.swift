import SwiftUI

@main
struct MusicFormatSwitcherApp: App {
    @StateObject private var monitor = MusicMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
        } label: {
            Image(systemName: monitor.isEnabled ? "waveform" : "waveform.slash")
        }
        .menuBarExtraStyle(.window)
    }
}
