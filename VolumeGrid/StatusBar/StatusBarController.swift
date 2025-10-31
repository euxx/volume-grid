import AppKit
import Combine

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
    private var volumeChangeHandler: ((CGFloat) -> Void)?
    private var isVolumeControlAvailable = false

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
        let initialDevice = volumeMonitor.currentDevice?.name ?? "Unknown Device"
        isVolumeControlAvailable = volumeMonitor.isCurrentDeviceVolumeSupported
        volumeChangeHandler = { [weak volumeMonitor] ratio in
            guard let monitor = volumeMonitor else { return }
            Task { @MainActor in
                monitor.setVolume(scalar: Float32(ratio))
            }
        }
        let formattedVolume = formattedVolumeText(for: initialVolume)

        volumeMenuView.update(
            percentage: initialVolume,
            formattedVolume: formattedVolume,
            deviceName: initialDevice
        )
        applyVolumeInteractionState(isVolumeControlAvailable)

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
        Task { @MainActor in
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

            volumeMonitor.$isCurrentDeviceVolumeSupported
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isSupported in
                    self?.updateVolumeInteraction(isSupported: isSupported)
                }
                .store(in: &subscriptions)
        }
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
            ?? "Unknown"
        let build =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"

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
        let formatted = formattedVolumeText(for: latestVolume)
        volumeMenuView.update(
            percentage: latestVolume,
            formattedVolume: formatted,
            deviceName: latestDeviceName
        )
        menu.itemChanged(volumeMenuItem)
    }

    private func updateVolumeInteraction(isSupported: Bool) {
        isVolumeControlAvailable = isSupported
        applyVolumeInteractionState(isSupported)
        refreshVolumeMenu()
    }

    private func applyVolumeInteractionState(_ isSupported: Bool) {
        if isSupported {
            volumeMenuView.setVolumeChangeHandler(volumeChangeHandler)
        } else {
            volumeMenuView.setVolumeChangeHandler(nil)
        }
    }

    private func formattedVolumeText(for percentage: Int) -> String {
        guard isVolumeControlAvailable else { return "Not Supported" }
        return VolumeFormatter.formattedVolumeString(for: percentage)
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

// MARK: - Status Bar UI Components

private final class LinearProgressView: NSView {
    var trackColor: NSColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6) {
        didSet { needsDisplay = true }
    }
    var fillColor: NSColor = NSColor.systemGray {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = 2 {
        didSet { needsDisplay = true }
    }

    var progress: CGFloat {
        get { storedProgress }
        set {
            let clamped = max(0, min(newValue, 1))
            guard abs(clamped - storedProgress) > .ulpOfOne else { return }
            storedProgress = clamped
            needsDisplay = true
        }
    }

    private var storedProgress: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackPath = NSBezierPath(
            roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        trackColor.setFill()
        trackPath.fill()

        if storedProgress > 0 {
            var fillRect = bounds
            fillRect.size.width = bounds.width * storedProgress
            fillRect.size.width = min(fillRect.width, bounds.width)
            let fillPath = NSBezierPath(
                roundedRect: fillRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
            fillColor.setFill()
            fillPath.fill()
        }
    }
}

final class StatusBarVolumeView: NSView {
    private let iconView = NSImageView()
    private let progressBackgroundView = NSView()
    private let progressView = NSView()
    private var progressWidthConstraint: NSLayoutConstraint!
    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!

    private let progressWidth: CGFloat = 20.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews()
        update(percentage: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor.controlTextColor

        progressBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        progressBackgroundView.wantsLayer = true
        progressBackgroundView.layer?.backgroundColor =
            NSColor.systemGray.withAlphaComponent(0.3).cgColor
        progressBackgroundView.layer?.cornerRadius = 1

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.systemGray.cgColor
        progressView.layer?.cornerRadius = 1

        addSubview(iconView)
        addSubview(progressBackgroundView)
        addSubview(progressView)

        progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 20)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 20)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            progressBackgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressBackgroundView.widthAnchor.constraint(equalToConstant: progressWidth),
            progressBackgroundView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10),
            progressBackgroundView.heightAnchor.constraint(equalToConstant: 2),

            progressView.leadingAnchor.constraint(equalTo: progressBackgroundView.leadingAnchor),
            progressView.bottomAnchor.constraint(equalTo: progressBackgroundView.bottomAnchor),
            progressView.topAnchor.constraint(equalTo: progressBackgroundView.topAnchor),
            progressWidthConstraint,
        ])
    }

    func update(percentage: Int) {
        let clamped = percentage.clamped(to: 0...100)
        let icon = VolumeIconHelper.icon(for: clamped)

        iconView.image = NSImage(
            systemSymbolName: icon.symbolName, accessibilityDescription: "Volume")
        iconWidthConstraint.constant = icon.size
        iconHeightConstraint.constant = icon.size
        progressWidthConstraint.constant = CGFloat(clamped) / 100.0 * progressWidth
    }
}

final class VolumeMenuItemView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let progressView = LinearProgressView()
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 12
    private let interItemSpacing: CGFloat = 8
    private let iconSize: CGFloat = 16
    private var onVolumeChange: ((CGFloat) -> Void)?
    private var isDragging = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: 280, height: 56)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews()
        update(percentage: 0, formattedVolume: "0", deviceName: "Unknown Device")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor.controlTextColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        progressView.trackColor = NSColor.controlBackgroundColor
        progressView.fillColor = NSColor.systemGray
        progressView.cornerRadius = 2

        addSubview(iconView)
        addSubview(label)
        addSubview(progressView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            iconView.centerYAnchor.constraint(equalTo: label.centerYAnchor),

            label.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor, constant: horizontalPadding / 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),

            progressView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: horizontalPadding),
            progressView.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -horizontalPadding),
            progressView.topAnchor.constraint(
                equalTo: label.bottomAnchor, constant: interItemSpacing),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
        progressView.progress = 0
    }

    func setVolumeChangeHandler(_ handler: ((CGFloat) -> Void)?) {
        onVolumeChange = handler
    }

    func update(percentage: Int, formattedVolume: String, deviceName: String) {
        let clamped = percentage.clamped(to: 0...100)
        let icon = VolumeIconHelper.icon(for: clamped)

        let config = NSImage.SymbolConfiguration(pointSize: icon.size, weight: .regular)
        let image = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: "Volume")
        iconView.image = image?.withSymbolConfiguration(config)
        label.stringValue = "\(deviceName) - \(formattedVolume)"
        progressView.progress = CGFloat(clamped) / 100.0
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard onVolumeChange != nil else {
            super.mouseDown(with: event)
            return
        }
        isDragging = true
        updateVolume(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else {
            super.mouseDragged(with: event)
            return
        }
        updateVolume(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            super.mouseUp(with: event)
            return
        }
        isDragging = false
        updateVolume(with: event)
    }

    private func updateVolume(with event: NSEvent) {
        guard let handler = onVolumeChange else { return }

        let pointInProgress = progressView.convert(event.locationInWindow, from: nil)
        let bounds = progressView.bounds
        guard bounds.width > 0 else { return }

        let clampedX = min(max(pointInProgress.x, 0), bounds.width)
        let ratio = clampedX / bounds.width

        progressView.progress = ratio
        DispatchQueue.global(qos: .userInitiated).async {
            handler(ratio)
        }
    }
}
