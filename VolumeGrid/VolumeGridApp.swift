import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private let volumeMonitor = VolumeMonitor()
    private let launchAtLoginController = LaunchAtLoginController()
    private var hudController: HUDController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Treat the app as an accessory so it stays out of the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)

        hudController = HUDController(volumeMonitor: volumeMonitor)
        statusBarController = StatusBarController(
            volumeMonitor: volumeMonitor,
            launchAtLoginController: launchAtLoginController
        )

        volumeMonitor.startListening()
        volumeMonitor.getAudioDevices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeMonitor.stopListening()
    }
}

@main
struct VolumeGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Remove the WindowGroup so the app runs in the background.
        Settings {
            EmptyView()
        }
    }
}
