import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private let volumeMonitor = VolumeMonitor()
    private let launchAtLoginController = LaunchAtLoginController()
    private let hudManager = HUDManager()
    private var statusBarController: StatusBarController?
    private var hudSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Treat the app as an accessory so it stays out of the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)

        // Subscribe to HUD events directly
        hudSubscription = volumeMonitor.hudEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.hudManager.showHUD(
                    volumeScalar: event.volumeScalar,
                    deviceName: event.deviceName,
                    isMuted: event.isMuted,
                    isUnsupported: event.isUnsupported
                )
            }

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
