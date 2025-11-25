import Cocoa

@MainActor
final class VolumeBlocksView: NSView {
    private let blockCount = 16
    private let blockWidth: CGFloat = 10
    private let blockHeight: CGFloat = 6
    private let blockSpacing: CGFloat = 1
    private let cornerRadius: CGFloat = 0.5
    private var style: HUDStyle
    private var blockLayers: [CAShapeLayer] = []
    private var fillLayers: [CAShapeLayer] = []

    private var totalWidth: CGFloat {
        CGFloat(blockCount) * blockWidth + CGFloat(blockCount - 1) * blockSpacing
    }

    init(style: HUDStyle) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor =
            NSColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 0.5).cgColor
        createBlockLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        .init(width: totalWidth, height: blockHeight)
    }

    private func createBlockLayers() {
        blockLayers.removeAll()
        fillLayers.removeAll()

        if let sublayers = layer?.sublayers {
            for sublayer in sublayers {
                sublayer.removeFromSuperlayer()
            }
        }

        for index in 0..<blockCount {
            let x = CGFloat(index) * (blockWidth + blockSpacing)
            let blockRect = CGRect(x: x, y: 0, width: blockWidth, height: blockHeight)
            let blockPath = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: blockWidth, height: blockHeight),
                cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            let blockLayer = CAShapeLayer()
            blockLayer.frame = blockRect
            blockLayer.path = blockPath
            blockLayer.fillColor = CGColor.clear

            let fillLayer = CAShapeLayer()
            fillLayer.frame = CGRect(x: 0, y: 0, width: 0, height: blockHeight)
            fillLayer.path = blockPath
            fillLayer.fillColor = style.blockFillColor.cgColor

            blockLayer.addSublayer(fillLayer)
            layer?.addSublayer(blockLayer)
            blockLayers.append(blockLayer)
            fillLayers.append(fillLayer)
        }
    }

    func update(style: HUDStyle, fillFraction: CGFloat) {
        self.style = style
        for fillLayer in fillLayers {
            fillLayer.fillColor = style.blockFillColor.cgColor
        }

        let clampedFraction = min(max(fillFraction, 0), 1)
        let totalBlocks = clampedFraction * CGFloat(blockCount)
        let roundedTotalBlocks =
            (totalBlocks / VolumeFormatter.quarterStep).rounded() * VolumeFormatter.quarterStep

        for (index, fillLayer) in fillLayers.enumerated() {
            let blockFill = min(max((roundedTotalBlocks - CGFloat(index)), 0), 1)
            fillLayer.isHidden = blockFill <= 0

            if blockFill > 0 {
                let fillWidth = blockWidth * blockFill
                let fillPath = CGPath(
                    roundedRect: CGRect(x: 0, y: 0, width: fillWidth, height: blockHeight),
                    cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                fillLayer.path = fillPath
                var frame = fillLayer.frame
                frame.size.width = fillWidth
                fillLayer.frame = frame
            }
        }
    }
}
