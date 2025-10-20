import SwiftUI

@main
struct VolumeMonitorApp: App {
    @StateObject private var volumeMonitor = VolumeMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(volumeMonitor)
        }
    }
}
