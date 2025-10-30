import Cocoa

final class VolumeBlocksView: NSView {
    private let blockCount = 16
    private let blockWidth: CGFloat = 14
    private let blockHeight: CGFloat = 6
    private let blockSpacing: CGFloat = 2
    private let cornerRadius: CGFloat = 0.5
    private var style: HUDStyle
    private var blockLayers: [CALayer] = []
    private var fillLayers: [CALayer] = []

    private var totalWidth: CGFloat {
        CGFloat(blockCount) * blockWidth + CGFloat(blockCount - 1) * blockSpacing
    }

    init(style: HUDStyle) {
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        createBlockLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: totalWidth, height: blockHeight)
    }

    private func createBlockLayers() {
        blockLayers.removeAll()
        fillLayers.removeAll()

        let containerLayer = CALayer()
        containerLayer.frame = CGRect(
            x: 0, y: 0, width: totalWidth, height: blockHeight)
        containerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(containerLayer)

        for index in 0..<blockCount {
            let blockLayer = CALayer()
            blockLayer.frame = CGRect(
                x: CGFloat(index) * (blockWidth + blockSpacing),
                y: 0,
                width: blockWidth,
                height: blockHeight
            )
            blockLayer.cornerRadius = cornerRadius
            blockLayer.backgroundColor = style.blockEmptyColor.cgColor

            let fillLayer = CALayer()
            fillLayer.cornerRadius = cornerRadius
            fillLayer.backgroundColor = style.blockFillColor.cgColor
            fillLayer.frame = CGRect(x: 0, y: 0, width: 0, height: blockHeight)

            blockLayer.addSublayer(fillLayer)
            containerLayer.addSublayer(blockLayer)
            blockLayers.append(blockLayer)
            fillLayers.append(fillLayer)
        }
    }

    func update(style: HUDStyle, fillFraction: CGFloat) {
        self.style = style
        for blockLayer in blockLayers {
            blockLayer.backgroundColor = style.blockEmptyColor.cgColor
        }
        for fillLayer in fillLayers {
            fillLayer.backgroundColor = style.blockFillColor.cgColor
        }

        let clampedFraction = max(0, min(1, fillFraction))
        let totalBlocks = clampedFraction * CGFloat(blockCount)

        for (index, fillLayer) in fillLayers.enumerated() {
            var blockFill = totalBlocks - CGFloat(index)
            blockFill = max(0, min(1, blockFill))
            blockFill = (blockFill * 4).rounded() / 4
            if blockFill <= 0 {
                fillLayer.isHidden = true
                fillLayer.frame = CGRect(x: 0, y: 0, width: 0, height: blockHeight)
            } else {
                fillLayer.isHidden = false
                fillLayer.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: blockWidth * blockFill,
                    height: blockHeight
                )
            }
        }
    }
}
