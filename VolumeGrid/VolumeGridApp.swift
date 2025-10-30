import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var volumeMonitor: VolumeMonitor?
    private var volumeSubscriber: AnyCancellable?
    private var deviceSubscriber: AnyCancellable?
    private var volumeMenuItem: NSMenuItem?
    private var statusBarVolumeView: StatusBarVolumeView?
    private var volumeMenuContentView: VolumeMenuItemView?
    private var launchAtLoginMenuItem: NSMenuItem?
    private let launchAtLoginController = LaunchAtLoginController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Treat the app as an accessory so it stays out of the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)

        // Start the volume monitor.
        volumeMonitor = VolumeMonitor()
        volumeMonitor?.startListening()
        volumeMonitor?.getAudioDevices()

        // Create the menu bar status item.
        setupStatusBarItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeMonitor?.stopListening()
        volumeSubscriber?.cancel()
        deviceSubscriber?.cancel()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 24)

        if let button = statusItem?.button {
            // Attach the custom view with the icon and progress indicator.
            let statusView = StatusBarVolumeView()
            button.addSubview(statusView)
            NSLayoutConstraint.activate([
                statusView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                statusView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            let initialVolume = volumeMonitor?.volumePercentage ?? 0
            statusView.update(percentage: initialVolume)
            statusBarVolumeView = statusView
        }

        // Build the status menu.
        let menu = NSMenu()

        // Add the menu item that shows the current volume (with a progress bar).
        let volumeItem = NSMenuItem()

        // Create the custom view that holds the text and progress bar.
        let initialVolume = volumeMonitor?.volumePercentage ?? 0
        let initialDevice = volumeMonitor?.currentDevice?.name ?? "Unknown Device"
        let volumeView = VolumeMenuItemView()
        volumeView.update(
            percentage: initialVolume,
            formattedVolume: VolumeFormatter.formattedVolumeString(for: initialVolume),
            deviceName: initialDevice
        )
        volumeView.setVolumeChangeHandler { [weak self] ratio in
            self?.volumeMonitor?.setVolume(scalar: Float32(ratio))
        }
        volumeItem.view = volumeView
        volumeItem.isEnabled = true
        menu.addItem(volumeItem)
        volumeMenuItem = volumeItem
        volumeMenuContentView = volumeView

        menu.minimumWidth = max(menu.minimumWidth, volumeView.intrinsicContentSize.width)

        menu.addItem(NSMenuItem.separator())

        // Add the launch-at-login toggle.
        let launchAtLoginItem = NSMenuItem(
            title: "Start at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = launchAtLoginController.isEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)
        launchAtLoginMenuItem = launchAtLoginItem

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Add the quit action.
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusMenu = menu

        // Keep menu volume and device information in sync.
        volumeSubscriber = volumeMonitor?.$volumePercentage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                guard let self else { return }

                // Refresh the progress indicator below the status bar icon.
                DispatchQueue.main.async {
                    self.statusBarVolumeView?.update(percentage: volume)
                }

                // Update the custom view inside the menu.
                if let volumeItem = self.volumeMenuItem,
                    let menuView = self.volumeMenuContentView
                {
                    let formatted = VolumeFormatter.formattedVolumeString(for: volume)
                    let deviceName = self.volumeMonitor?.currentDevice?.name ?? "Unknown Device"
                    DispatchQueue.main.async {
                        menuView.update(
                            percentage: volume,
                            formattedVolume: formatted,
                            deviceName: deviceName
                        )
                        self.statusMenu?.itemChanged(volumeItem)
                    }
                }
            }

        deviceSubscriber = volumeMonitor?.$currentDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let self,
                    let volumeItem = self.volumeMenuItem,
                    let menuView = self.volumeMenuContentView
                else { return }
                let name = device?.name ?? "Unknown Device"
                let volume = self.volumeMonitor?.volumePercentage ?? 0
                let formatted = VolumeFormatter.formattedVolumeString(for: volume)
                menuView.update(
                    percentage: volume,
                    formattedVolume: formatted,
                    deviceName: name
                )
                self.statusMenu?.itemChanged(volumeItem)
            }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func showAbout() {
        let appName =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "VolumeGrid"
        let version =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "Unknown Version"

        let build =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Unknown Build"

        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = "Version: \(version) (Build \(build))"
        alert.alertStyle = .informational

        let contactString = NSMutableAttributedString(string: "GitHub")
        let range = (contactString.string as NSString).range(of: "GitHub")
        if range.location != NSNotFound {
            contactString.addAttribute(
                .link,
                value: "https://github.com/euxx/VolumeGrid",
                range: range
            )
        }

        let contactLabel = NSTextField(labelWithAttributedString: contactString)
        contactLabel.allowsEditingTextAttributes = true
        contactLabel.isSelectable = true
        contactLabel.lineBreakMode = .byWordWrapping
        contactLabel.maximumNumberOfLines = 0
        contactLabel.translatesAutoresizingMaskIntoConstraints = false
        alert.accessoryView = contactLabel
        contactLabel.widthAnchor.constraint(equalToConstant: 280).isActive = true

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func toggleLaunchAtLogin() {
        let targetState = !launchAtLoginController.isEnabled()
        launchAtLoginMenuItem?.isEnabled = false

        launchAtLoginController.setEnabled(targetState) { [weak self] result in
            guard let self else { return }
            defer { self.launchAtLoginMenuItem?.isEnabled = true }

            switch result {
            case .success(let enabled):
                self.launchAtLoginMenuItem?.state = enabled ? .on : .off
            case .failure(let error):
                self.launchAtLoginMenuItem?.state =
                    self.launchAtLoginController.isEnabled() ? .on : .off
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Launch at Login"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
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
