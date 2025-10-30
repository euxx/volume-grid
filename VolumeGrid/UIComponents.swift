import AppKit

/// Simple linear progress view that draws a rounded track and fill using AppKit drawing.
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
            // Ensure the fill rect respects the corner radius by not exceeding bounds width.
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

/// Compact status bar view that shows the current volume with an icon and a progress bar.
final class StatusBarVolumeView: NSView {
    private let iconView = NSImageView()
    private let progressBackgroundView = NSView()
    private let progressView = NSView()
    private var progressWidthConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?

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
        wantsLayer = false

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
        progressWidthConstraint?.isActive = true

        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 20)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 20)
        iconWidthConstraint?.isActive = true
        iconHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),

            progressBackgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressBackgroundView.widthAnchor.constraint(equalToConstant: progressWidth),
            progressBackgroundView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10),
            progressBackgroundView.heightAnchor.constraint(equalToConstant: 2),

            progressView.leadingAnchor.constraint(equalTo: progressBackgroundView.leadingAnchor),
            progressView.bottomAnchor.constraint(equalTo: progressBackgroundView.bottomAnchor),
            progressView.topAnchor.constraint(equalTo: progressBackgroundView.topAnchor),
        ])
    }

    func update(percentage: Int) {
        let clamped = max(0, min(percentage, 100))

        var iconName: String
        var iconSize: CGFloat = 20

        if clamped == 0 {
            // Muted - smaller icon
            iconName = "speaker.slash"
            iconSize = 15
        } else if clamped < 33 {
            // Low volume
            iconName = "speaker.wave.1"
            iconSize = 17
        } else if clamped < 66 {
            // Medium volume
            iconName = "speaker.wave.2"
            iconSize = 19
        } else {
            // High volume
            iconName = "speaker.wave.3"
            iconSize = 21
        }

        iconView.image = NSImage(
            systemSymbolName: iconName, accessibilityDescription: "Volume")
        iconWidthConstraint?.constant = iconSize
        iconHeightConstraint?.constant = iconSize
        progressWidthConstraint?.constant = CGFloat(clamped) / 100.0 * progressWidth
    }
}

/// Custom view used inside the menu item to display the volume value and a linear indicator.
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
        let clamped = max(0, min(percentage, 100))

        // Determine icon based on volume level
        var iconName: String
        var iconSize: CGFloat = 20
        if clamped == 0 {
            // Muted
            iconName = "speaker.slash"
            iconSize = 15
        } else if clamped < 33 {
            // Low volume
            iconName = "speaker.wave.1"
            iconSize = 17
        } else if clamped < 66 {
            // Medium volume
            iconName = "speaker.wave.2"
            iconSize = 19
        } else {
            // High volume
            iconName = "speaker.wave.3"
            iconSize = 21
        }

        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Volume")
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
        handler(ratio)
    }
}
