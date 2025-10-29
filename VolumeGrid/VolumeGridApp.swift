import AppKit
import Combine
import ServiceManagement
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
            formattedVolume: formattedVolumeString(for: initialVolume),
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
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
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
                    let formatted = self.formattedVolumeString(for: volume)
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
                let formatted = self.formattedVolumeString(for: volume)
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

    // Convert the block count into a readable string (simplified to only show the current volume).
    private func formatVolumeString(quarterBlocks: CGFloat) -> String {
        let integerPart = Int(quarterBlocks)
        let fractionalPart = quarterBlocks - CGFloat(integerPart)
        let epsilon: CGFloat = 0.001

        var fractionString = ""
        if fractionalPart >= epsilon && abs(fractionalPart - 1.0) >= epsilon {
            switch fractionalPart {
            case (0.25 - epsilon)...(0.25 + epsilon):
                fractionString = "1/4"
            case (0.5 - epsilon)...(0.5 + epsilon):
                fractionString = "2/4"
            case (0.75 - epsilon)...(0.75 + epsilon):
                fractionString = "3/4"
            default:
                fractionString = String(format: "%.2f", fractionalPart)
            }
        }

        if fractionString.isEmpty {
            return "\(integerPart)"
        } else if integerPart == 0 {
            return "\(fractionString)"
        } else {
            return "\(integerPart)+\(fractionString)"
        }
    }

    private func formattedVolumeString(for percentage: Int) -> String {
        let clamped = max(0, min(percentage, 100))
        let volumeScalar = CGFloat(clamped) / 100.0
        let totalBlocks = volumeScalar * 16.0
        let quarterBlocks = (totalBlocks * 4).rounded() / 4
        return formatVolumeString(quarterBlocks: quarterBlocks)
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = isLaunchAtLoginEnabled()
        if enabled {
            disableLaunchAtLogin()
        } else {
            enableLaunchAtLogin()
        }
        // Refresh the menu state.
        launchAtLoginMenuItem?.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS versions: check plist
            let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents")
            let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")
            return FileManager.default.fileExists(atPath: plistPath.path)
        }
    }

    private func enableLaunchAtLogin() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            if #available(macOS 13.0, *) {
                do {
                    try SMAppService.mainApp.register()
                    DispatchQueue.main.async {
                        self.launchAtLoginMenuItem?.state = .on
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showError(
                            "Failed to enable launch at login: \(error.localizedDescription)")
                    }
                }
            } else {
                // Fallback to plist-based approach for older macOS
                self.enableLaunchAtLoginLegacy()
            }
        }
    }

    private func disableLaunchAtLogin() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            if #available(macOS 13.0, *) {
                do {
                    try SMAppService.mainApp.unregister()
                    DispatchQueue.main.async {
                        self.launchAtLoginMenuItem?.state = .off
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showError(
                            "Failed to disable launch at login: \(error.localizedDescription)")
                    }
                }
            } else {
                // Fallback to plist-based approach for older macOS
                self.disableLaunchAtLoginLegacy()
            }
        }
    }

    private func enableLaunchAtLoginLegacy() {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")

        // Ensure the directory exists.
        do {
            try FileManager.default.createDirectory(
                at: launchAgentsPath, withIntermediateDirectories: true)
        } catch {
            DispatchQueue.main.async {
                self.showError(
                    "Failed to create LaunchAgents directory: \(error.localizedDescription)")
            }
            return
        }

        let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")
        let appPath = Bundle.main.bundlePath

        let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>eux.volumegrid</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """

        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            // Load the Launch Agent.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", plistPath.path]
            try process.run()
            process.waitUntilExit()

            DispatchQueue.main.async {
                self.launchAtLoginMenuItem?.state = .on
            }
        } catch {
            DispatchQueue.main.async {
                self.showError("Failed to enable launch at login: \(error.localizedDescription)")
            }
        }
    }

    private func disableLaunchAtLoginLegacy() {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")

        do {
            // Unload the Launch Agent.
            let unloadProcess = Process()
            unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unloadProcess.arguments = ["unload", plistPath.path]
            try unloadProcess.run()
            unloadProcess.waitUntilExit()

            // Remove the plist file.
            try FileManager.default.removeItem(at: plistPath)

            DispatchQueue.main.async {
                self.launchAtLoginMenuItem?.state = .off
            }
        } catch {
            DispatchQueue.main.async {
                self.showError("Failed to disable launch at login: \(error.localizedDescription)")
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
