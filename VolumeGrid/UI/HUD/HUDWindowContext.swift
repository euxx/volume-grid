import Cocoa

/// Stores references to HUD window components that need dynamic updates
final class HUDWindowContext {
    let screenID: CGDirectDisplayID
    let window: NSWindow

    // Store only components that need runtime updates
    let containerView: NSView
    let contentStack: NSStackView
    let iconContainer: NSView
    let iconView: NSImageView
    let textStack: NSStackView
    let deviceLabel: NSTextField
    let volumeLabel: NSTextField
    let blocksView: VolumeBlocksView

    init(
        screenID: CGDirectDisplayID,
        window: NSWindow,
        containerView: NSView,
        contentStack: NSStackView,
        iconContainer: NSView,
        iconView: NSImageView,
        textStack: NSStackView,
        deviceLabel: NSTextField,
        volumeLabel: NSTextField,
        blocksView: VolumeBlocksView
    ) {
        self.screenID = screenID
        self.window = window
        self.containerView = containerView
        self.contentStack = contentStack
        self.iconContainer = iconContainer
        self.iconView = iconView
        self.textStack = textStack
        self.deviceLabel = deviceLabel
        self.volumeLabel = volumeLabel
        self.blocksView = blocksView
    }
}
