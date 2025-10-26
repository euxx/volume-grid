import AppKit

/// Compact status bar view that shows the current volume with an icon and a progress bar.
final class StatusBarVolumeView: NSView {
    private let iconView = NSImageView()
    private let progressBackgroundView = NSView()
    private let progressView = NSView()
    private var progressWidthConstraint: NSLayoutConstraint?

    private let progressWidth: CGFloat = 14.0

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
        wantsLayer = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor.controlTextColor

        progressBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        progressBackgroundView.wantsLayer = true
        progressBackgroundView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.3).cgColor
        progressBackgroundView.layer?.cornerRadius = 1

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.systemGray.cgColor
        progressView.layer?.cornerRadius = 1

        addSubview(iconView)
        addSubview(progressBackgroundView)
        addSubview(progressView)

        progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 22),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            progressBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            progressBackgroundView.trailingAnchor.constraint(equalTo: leadingAnchor, constant: 3 + progressWidth),
            progressBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            progressBackgroundView.heightAnchor.constraint(equalToConstant: 2),

            progressView.leadingAnchor.constraint(equalTo: progressBackgroundView.leadingAnchor),
            progressView.bottomAnchor.constraint(equalTo: progressBackgroundView.bottomAnchor),
            progressView.topAnchor.constraint(equalTo: progressBackgroundView.topAnchor)
        ])
    }

    func update(percentage: Int) {
        let clamped = max(0, min(percentage, 100))
        let iconName = clamped == 0 ? "speaker.slash" : "speaker.wave.2"
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Volume")
        progressWidthConstraint?.constant = CGFloat(clamped) / 100.0 * progressWidth
    }
}

/// Custom view used inside the menu item to display the volume value and a linear indicator.
final class VolumeMenuItemView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let progressContainer = NSView()
    private let progressBackgroundView = NSView()
    private let progressView = NSView()
    private var progressWidthConstraint: NSLayoutConstraint?
    private var progressFraction: CGFloat = 0
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 12
    private let interItemSpacing: CGFloat = 8

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 56)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews()
        update(percentage: 0, formattedVolume: "0", deviceName: "未知设备")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor

        progressContainer.translatesAutoresizingMaskIntoConstraints = false

        progressBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        progressBackgroundView.wantsLayer = true
        progressBackgroundView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        progressBackgroundView.layer?.cornerRadius = 2

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.systemGray.cgColor
        progressView.layer?.cornerRadius = 2

        addSubview(label)
        addSubview(progressContainer)
        progressContainer.addSubview(progressBackgroundView)
        progressContainer.addSubview(progressView)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),

            progressContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            progressContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            progressContainer.topAnchor.constraint(equalTo: label.bottomAnchor, constant: interItemSpacing),
            progressContainer.heightAnchor.constraint(equalToConstant: 4),
            progressContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding),

            progressBackgroundView.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressBackgroundView.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progressBackgroundView.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressBackgroundView.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),

            progressView.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressView.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressView.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor)
        ])

        progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true
    }

    func update(percentage: Int, formattedVolume: String, deviceName: String) {
        let clamped = max(0, min(percentage, 100))
        label.stringValue = "\(deviceName) - \(formattedVolume)"
        progressFraction = CGFloat(clamped) / 100.0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateProgressWidth()
    }

    private func updateProgressWidth() {
        guard let progressWidthConstraint else { return }
        let width = progressContainer.bounds.width
        progressWidthConstraint.constant = width * progressFraction
    }
}
