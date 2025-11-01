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
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
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

        let containerLayer = CALayer()
        containerLayer.frame = .init(
            x: 0, y: 0, width: totalWidth, height: blockHeight)
        containerLayer.backgroundColor = CGColor.clear
        layer?.addSublayer(containerLayer)

        for index in 0..<blockCount {
            let blockLayer = CALayer()
            blockLayer.frame = .init(
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
            fillLayer.frame = .init(x: 0, y: 0, width: 0, height: blockHeight)

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

        let clampedFraction = fillFraction.clamped(to: 0...1)
        let totalBlocks = clampedFraction * CGFloat(blockCount)

        for (index, fillLayer) in fillLayers.enumerated() {
            let blockFill = ((totalBlocks - CGFloat(index)).clamped(to: 0...1) * 4).rounded() / 4
            fillLayer.isHidden = blockFill <= 0
            fillLayer.frame = .init(
                x: 0,
                y: 0,
                width: blockWidth * blockFill,
                height: blockHeight
            )
        }
    }
}
