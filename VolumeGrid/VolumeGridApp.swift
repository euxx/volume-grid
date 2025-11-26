import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var volumeMonitor: VolumeMonitor?
    private var launchAtLoginController: LaunchAtLoginController?
    private var hudManager: HUDManager?
    private var statusBarController: StatusBarController?
    private var hudSubscription: AnyCancellable?

    private var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }

        NSApplication.shared.setActivationPolicy(.accessory)

        let monitor = VolumeMonitor()
        let loginController = LaunchAtLoginController()
        let hud = HUDManager()

        self.volumeMonitor = monitor
        self.launchAtLoginController = loginController
        self.hudManager = hud

        hudSubscription = monitor.hudEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak hud] event in
                hud?.showHUD(
                    volumeScalar: event.volumeScalar,
                    deviceName: event.deviceName,
                    isUnsupported: event.isUnsupported
                )
            }

        statusBarController = StatusBarController(
            volumeMonitor: monitor,
            launchAtLoginController: loginController
        )

        monitor.startListening()
        monitor.getAudioDevices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeMonitor?.stopListening()
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
