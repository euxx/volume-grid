import Cocoa

final class HUDWindowContext {
    let screenID: CGDirectDisplayID
    let window: NSWindow
    let containerView: NSView
    let contentStack: NSStackView
    let iconContainer: NSView
    let iconView: NSImageView
    let iconWidthConstraint: NSLayoutConstraint
    let iconHeightConstraint: NSLayoutConstraint
    let textStack: NSStackView
    let deviceLabel: NSTextField
    let volumeLabel: NSTextField
    let volumeWidthConstraint: NSLayoutConstraint
    let blocksView: VolumeBlocksView
    let blocksWidthConstraint: NSLayoutConstraint

    init(
        screenID: CGDirectDisplayID,
        window: NSWindow,
        containerView: NSView,
        contentStack: NSStackView,
        iconContainer: NSView,
        iconView: NSImageView,
        iconWidthConstraint: NSLayoutConstraint,
        iconHeightConstraint: NSLayoutConstraint,
        textStack: NSStackView,
        deviceLabel: NSTextField,
        volumeLabel: NSTextField,
        volumeWidthConstraint: NSLayoutConstraint,
        blocksView: VolumeBlocksView,
        blocksWidthConstraint: NSLayoutConstraint
    ) {
        self.screenID = screenID
        self.window = window
        self.containerView = containerView
        self.contentStack = contentStack
        self.iconContainer = iconContainer
        self.iconView = iconView
        self.iconWidthConstraint = iconWidthConstraint
        self.iconHeightConstraint = iconHeightConstraint
        self.textStack = textStack
        self.deviceLabel = deviceLabel
        self.volumeLabel = volumeLabel
        self.volumeWidthConstraint = volumeWidthConstraint
        self.blocksView = blocksView
        self.blocksWidthConstraint = blocksWidthConstraint
    }
}
