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

        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
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
    private let progressView = LinearProgressView()
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
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        progressView.trackColor = NSColor.controlBackgroundColor
        progressView.fillColor = NSColor.systemGray
        progressView.cornerRadius = 2

        addSubview(label)
        addSubview(progressView)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),

            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            progressView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: interItemSpacing),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding),
            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
        progressView.progress = 0
    }

    func update(percentage: Int, formattedVolume: String, deviceName: String) {
        let clamped = max(0, min(percentage, 100))
        label.stringValue = "\(deviceName) - \(formattedVolume)"
        progressView.progress = CGFloat(clamped) / 100.0
    }
}
