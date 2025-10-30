import AppKit
import Combine

/// Coordinates the status bar item, menu content, and user actions.
final class StatusBarController {
    private let volumeMonitor: VolumeMonitor
    private let launchAtLoginController: LaunchAtLoginController

    private let statusItem: NSStatusItem
    private let statusBarVolumeView = StatusBarVolumeView()
    private let menu = NSMenu()
    private let volumeMenuItem = NSMenuItem()
    private let volumeMenuView = VolumeMenuItemView()
    private let launchAtLoginMenuItem: NSMenuItem

    private var subscriptions = Set<AnyCancellable>()
    private var latestVolume: Int = 0
    private var latestDeviceName: String = "Unknown Device"

    init(volumeMonitor: VolumeMonitor, launchAtLoginController: LaunchAtLoginController) {
        self.volumeMonitor = volumeMonitor
        self.launchAtLoginController = launchAtLoginController

        statusItem = NSStatusBar.system.statusItem(withLength: 24)
        launchAtLoginMenuItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = launchAtLoginController.isEnabled() ? .on : .off

        setupStatusBarButton()
        setupMenu()
        bindVolumeUpdates()
    }

    // MARK: - Setup

    private func setupStatusBarButton() {
        guard let button = statusItem.button else { return }
        button.addSubview(statusBarVolumeView)
        NSLayoutConstraint.activate([
            statusBarVolumeView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            statusBarVolumeView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    private func setupMenu() {
        let initialVolume = volumeMonitor.volumePercentage
        let formattedVolume = VolumeFormatter.formattedVolumeString(for: initialVolume)
        let initialDevice = volumeMonitor.currentDevice?.name ?? "Unknown Device"

        volumeMenuView.update(
            percentage: initialVolume,
            formattedVolume: formattedVolume,
            deviceName: initialDevice
        )
        volumeMenuView.setVolumeChangeHandler { [weak volumeMonitor] ratio in
            volumeMonitor?.setVolume(scalar: Float32(ratio))
        }

        volumeMenuItem.view = volumeMenuView
        volumeMenuItem.isEnabled = true
        menu.addItem(volumeMenuItem)
        menu.minimumWidth = max(menu.minimumWidth, volumeMenuView.intrinsicContentSize.width)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        latestVolume = initialVolume
        latestDeviceName = initialDevice
        statusBarVolumeView.update(percentage: initialVolume)
    }

    private func bindVolumeUpdates() {
        volumeMonitor.$volumePercentage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.latestVolume = volume
                self?.statusBarVolumeView.update(percentage: volume)
                self?.refreshVolumeMenu()
            }
            .store(in: &subscriptions)

        volumeMonitor.$currentDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                self?.latestDeviceName = device?.name ?? "Unknown Device"
                self?.refreshVolumeMenu()
            }
            .store(in: &subscriptions)
    }

    // MARK: - Menu Actions

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func showAbout() {
        let appName =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "VolumeGrid"
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Unknown Version"
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
        launchAtLoginMenuItem.isEnabled = false

        launchAtLoginController.setEnabled(targetState) { [weak self] result in
            guard let self else { return }
            defer { self.launchAtLoginMenuItem.isEnabled = true }

            switch result {
            case .success(let enabled):
                self.launchAtLoginMenuItem.state = enabled ? .on : .off
            case .failure(let error):
                self.launchAtLoginMenuItem.state =
                    self.launchAtLoginController.isEnabled() ? .on : .off
                self.showError(error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func refreshVolumeMenu() {
        let formatted = VolumeFormatter.formattedVolumeString(for: latestVolume)
        volumeMenuView.update(
            percentage: latestVolume,
            formattedVolume: formatted,
            deviceName: latestDeviceName
        )
        menu.itemChanged(volumeMenuItem)
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
