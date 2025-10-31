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
        NSApplication.shared.setActivationPolicy(.accessory)

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
        Settings {
            EmptyView()
        }
    }
}
