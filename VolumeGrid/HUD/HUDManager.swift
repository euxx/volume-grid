import Cocoa
import Combine
import SwiftUI
import os

private let logger = Logger(subsystem: "com.volumegrid", category: "HUDManager")

struct HUDStyle {
    let shadowColor: NSColor
    let iconTintColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let blockFillColor: NSColor
}

struct HUDViewComponents {
    let iconView: NSImageView
    let textStack: NSStackView
    let deviceLabel: NSTextField
    let volumeLabel: NSTextField
    let blocksView: VolumeBlocksView
}

struct HUDConstraints {
    let iconWidth: NSLayoutConstraint
    let iconHeight: NSLayoutConstraint
    let volumeLabelWidth: NSLayoutConstraint
    let blocksWidth: NSLayoutConstraint
}

final class HUDWindowContext {
    let screenID: CGDirectDisplayID
    let window: NSWindow
    let containerView: NSView
    let contentStack: NSStackView
    let iconContainer: NSView
    let views: HUDViewComponents
    let constraints: HUDConstraints

    init(
        screenID: CGDirectDisplayID,
        window: NSWindow,
        containerView: NSView,
        contentStack: NSStackView,
        iconContainer: NSView,
        views: HUDViewComponents,
        constraints: HUDConstraints
    ) {
        self.screenID = screenID
        self.window = window
        self.containerView = containerView
        self.contentStack = contentStack
        self.iconContainer = iconContainer
        self.views = views
        self.constraints = constraints
    }
}

class HUDManager {
    private var hudWindows: [CGDirectDisplayID: HUDWindowContext] = [:]
    private var hideHUDTask: Task<Void, Never>?
    private var screenChangeCancellable: AnyCancellable?
    private var currentHUDCycleID: UInt64 = 0

    @MainActor
    init() {
        logger.debug("HUDManager initialized")
        syncHUDWindowsWithScreens()
        screenChangeCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncHUDWindowsWithScreens()
            }
    }

    deinit {
        hideHUDTask?.cancel()
        screenChangeCancellable?.cancel()
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    @MainActor
    private func makeHUDWindow(for screen: NSScreen, screenID: CGDirectDisplayID)
        -> HUDWindowContext
    {
        let window = NSWindow(
            contentRect: .init(
                x: 0, y: 0, width: VolumeGridConstants.HUD.width,
                height: VolumeGridConstants.HUD.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.collectionBehavior = [
            .transient,
            .ignoresCycle,
        ]
        window.ignoresMouseEvents = true

        let containerView = NSVisualEffectView(
            frame: .init(
                x: 0, y: 0, width: VolumeGridConstants.HUD.width,
                height: VolumeGridConstants.HUD.height))
        containerView.material = .hudWindow
        containerView.appearance = NSAppearance(named: .darkAqua)
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        let style = hudStyle()
        containerView.layer?.cornerRadius = VolumeGridConstants.HUD.cornerRadius
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor.darkGray.withAlphaComponent(0.7).cgColor
        containerView.layer?.borderWidth = 0.6
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        containerView.layer?.shadowColor = style.shadowColor.cgColor
        containerView.layer?.shadowOpacity = 0.6
        containerView.layer?.shadowOffset = .init(width: 0, height: 4)
        containerView.layer?.shadowRadius = 10
        window.contentView = containerView

        let contentStack = NSStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 0
        containerView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            contentStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: containerView.leadingAnchor,
                constant: VolumeGridConstants.HUD.marginX),
            contentStack.trailingAnchor.constraint(
                lessThanOrEqualTo: containerView.trailingAnchor,
                constant: -VolumeGridConstants.HUD.marginX),
        ])
        let topConstraint = contentStack.topAnchor.constraint(
            greaterThanOrEqualTo: containerView.topAnchor,
            constant: VolumeGridConstants.HUD.minVerticalPadding
        )
        topConstraint.priority = .defaultHigh
        topConstraint.isActive = true
        let bottomConstraint = contentStack.bottomAnchor.constraint(
            lessThanOrEqualTo: containerView.bottomAnchor,
            constant: -VolumeGridConstants.HUD.minVerticalPadding)
        bottomConstraint.priority = .defaultHigh
        bottomConstraint.isActive = true

        let iconContainerSize = VolumeGridConstants.HUD.Layout.iconSize
        let iconContainer = NSView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = style.iconTintColor
        iconContainer.addSubview(iconView)

        let iconWidthConstraint = iconView.widthAnchor.constraint(
            equalToConstant: iconContainerSize)
        let iconHeightConstraint = iconView.heightAnchor.constraint(
            equalToConstant: iconContainerSize)
        iconWidthConstraint.isActive = true
        iconHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: iconContainerSize),
            iconContainer.heightAnchor.constraint(equalToConstant: iconContainerSize),
        ])

        contentStack.addArrangedSubview(iconContainer)

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .horizontal
        textStack.alignment = .centerY
        textStack.spacing = VolumeGridConstants.HUD.Layout.textStackSpacing

        let leadingSpacer = NSView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadingSpacer.widthAnchor.constraint(
            equalToConstant: VolumeGridConstants.HUD.Layout.leadingSpacerWidth
        ).isActive = true

        let deviceLabel = NSTextField(labelWithString: "")
        deviceLabel.translatesAutoresizingMaskIntoConstraints = false
        deviceLabel.textColor = style.secondaryTextColor
        deviceLabel.font = .systemFont(ofSize: 12, weight: .regular)
        deviceLabel.alignment = .left
        deviceLabel.isBordered = false
        deviceLabel.backgroundColor = .clear
        deviceLabel.isEditable = false
        deviceLabel.isSelectable = false
        deviceLabel.lineBreakMode = .byTruncatingTail
        deviceLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        deviceLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let volumeLabel = NSTextField(labelWithString: "")
        volumeLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeLabel.textColor = style.primaryTextColor
        volumeLabel.font = .systemFont(ofSize: 12, weight: .regular)
        volumeLabel.alignment = .left
        volumeLabel.isBordered = false
        volumeLabel.backgroundColor = .clear
        volumeLabel.isEditable = false
        volumeLabel.isSelectable = false
        volumeLabel.lineBreakMode = .byClipping
        volumeLabel.setContentHuggingPriority(.required, for: .horizontal)
        volumeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let volumeWidthConstraint = volumeLabel.widthAnchor.constraint(equalToConstant: 0)
        volumeWidthConstraint.priority = .required
        volumeWidthConstraint.isActive = true

        textStack.addArrangedSubview(leadingSpacer)
        textStack.addArrangedSubview(deviceLabel)
        textStack.addArrangedSubview(volumeLabel)
        contentStack.addArrangedSubview(textStack)

        let blocksView = VolumeBlocksView(style: style)
        let blocksWidthConstraint = blocksView.widthAnchor.constraint(
            equalToConstant: blocksView.intrinsicContentSize.width)
        blocksWidthConstraint.priority = .required
        blocksWidthConstraint.isActive = true
        contentStack.addArrangedSubview(blocksView)
        blocksView.update(style: style, fillFraction: 0)

        let spacingIconToDevice = VolumeGridConstants.HUD.Layout.spacingIconToDevice
        let spacingDeviceToBlocks = VolumeGridConstants.HUD.Layout.spacingDeviceToBlocks
        contentStack.setCustomSpacing(spacingIconToDevice, after: iconContainer)
        contentStack.setCustomSpacing(spacingDeviceToBlocks, after: textStack)

        let screenFrame = screen.frame
        let windowOrigin = CGPoint(
            x: screenFrame.midX - VolumeGridConstants.HUD.width / 2,
            y: screenFrame.midY - VolumeGridConstants.HUD.height / 2
        )
        window.setFrameOrigin(windowOrigin)
        window.alphaValue = VolumeGridConstants.HUD.alpha

        let views = HUDViewComponents(
            iconView: iconView,
            textStack: textStack,
            deviceLabel: deviceLabel,
            volumeLabel: volumeLabel,
            blocksView: blocksView
        )

        let constraints = HUDConstraints(
            iconWidth: iconWidthConstraint,
            iconHeight: iconHeightConstraint,
            volumeLabelWidth: volumeWidthConstraint,
            blocksWidth: blocksWidthConstraint
        )

        return HUDWindowContext(
            screenID: screenID,
            window: window,
            containerView: containerView,
            contentStack: contentStack,
            iconContainer: iconContainer,
            views: views,
            constraints: constraints
        )
    }

    @MainActor
    private func syncHUDWindowsWithScreens() {
        var remaining = hudWindows
        var updated: [CGDirectDisplayID: HUDWindowContext] = [:]

        for screen in NSScreen.screens {
            guard let screenID = screenID(for: screen) else { continue }
            if let existing = remaining.removeValue(forKey: screenID) {
                updated[screenID] = existing
            } else {
                let context = makeHUDWindow(for: screen, screenID: screenID)
                updated[screenID] = context
            }
        }

        for (_, context) in remaining {
            context.window.close()
        }

        hudWindows = updated
    }

    private func calculateHUDWidth(
        deviceName: String,
        statusString: String
    ) -> (width: CGFloat, statusTextWidth: CGFloat) {
        let deviceNSString = NSString(string: deviceName + "  -")
        let deviceTextSize = deviceNSString.size(withAttributes: [
            .font: VolumeGridConstants.HUD.textFont
        ])

        let statusNSString = NSString(string: statusString)
        let statusTextSize = statusNSString.size(withAttributes: [
            .font: VolumeGridConstants.HUD.textFont
        ])
        let maxVolumeSampleString = VolumeFormatter.formatVolumeCount(quarterBlocks: 15.75)
        let maxVolumeSampleWidth = NSString(string: maxVolumeSampleString)
            .size(withAttributes: [.font: VolumeGridConstants.HUD.textFont]).width
        let effectiveStatusTextWidth = max(statusTextSize.width, maxVolumeSampleWidth)

        let gapBetweenDeviceAndCount = VolumeGridConstants.HUD.Layout.textStackSpacing
        let combinedWidth =
            deviceTextSize.width + gapBetweenDeviceAndCount + effectiveStatusTextWidth
        let dynamicHudWidth = max(
            VolumeGridConstants.HUD.width, combinedWidth + VolumeGridConstants.HUD.marginX)

        return (dynamicHudWidth, effectiveStatusTextWidth)
    }

    @MainActor
    func showHUD(
        volumeScalar: CGFloat, deviceName: String?, isUnsupported: Bool = false
    ) {
        currentHUDCycleID &+= 1
        let cycleID = currentHUDCycleID
        logger.debug("showHUD: volume=\(volumeScalar, privacy: .public), cycleID=\(cycleID)")

        let epsilon = VolumeGridConstants.Audio.volumeEpsilon
        let clampedScalar = volumeScalar.clamped(to: 0...1)
        let isMutedForDisplay = clampedScalar <= epsilon
        let displayedScalar = isMutedForDisplay ? 0 : clampedScalar

        let spacingIconToDevice: CGFloat =
            isUnsupported
            ? VolumeGridConstants.HUD.Layout.spacingIconToDeviceUnsupported
            : VolumeGridConstants.HUD.Layout.spacingIconToDevice
        let spacingDeviceToBlocks: CGFloat =
            isUnsupported
            ? VolumeGridConstants.HUD.Layout.spacingDeviceToBlocksUnsupported
            : VolumeGridConstants.HUD.Layout.spacingDeviceToBlocks

        let deviceName = deviceName ?? "Unknown Device"
        let statusString =
            isUnsupported
            ? "Not Supported"
            : VolumeFormatter.formattedVolumeString(forScalar: displayedScalar)

        let (dynamicHudWidth, effectiveStatusTextWidth) = calculateHUDWidth(
            deviceName: deviceName,
            statusString: statusString
        )
        let gapBetweenDeviceAndCount = VolumeGridConstants.HUD.Layout.textStackSpacing

        syncHUDWindowsWithScreens()

        for screen in NSScreen.screens {
            guard
                let screenID = screenID(for: screen),
                let context = hudWindows[screenID]
            else { continue }

            let hudWindow = context.window
            let isAlreadyVisible = hudWindow.isVisible && hudWindow.alphaValue > 0.1

            let style = hudStyle()
            let screenFrame = screen.frame
            let newWindowFrame = NSRect(
                x: screenFrame.midX - dynamicHudWidth / 2,
                y: screenFrame.midY - VolumeGridConstants.HUD.height / 2 - 40,
                width: dynamicHudWidth,
                height: VolumeGridConstants.HUD.height
            )
            hudWindow.setFrame(newWindowFrame, display: true)

            let containerView = context.containerView
            containerView.frame = .init(
                x: 0, y: 0, width: dynamicHudWidth, height: VolumeGridConstants.HUD.height)
            containerView.layer?.shadowColor = style.shadowColor.cgColor
            containerView.layer?.shadowOpacity = 1.0

            let volumePercentage = Int(clampedScalar * 100)
            let icon = VolumeIconHelper.hudIcon(
                for: volumePercentage,
                isUnsupported: isUnsupported
            )

            if let speakerImage = NSImage(
                systemSymbolName: icon.symbolName, accessibilityDescription: "Volume")
            {
                context.views.iconView.image = speakerImage
            } else if let fallbackImage = NSImage(
                named: NSImage.touchBarAudioOutputVolumeHighTemplateName)
            {
                context.views.iconView.image = fallbackImage
            } else {
                context.views.iconView.image = NSImage(
                    size: .init(width: icon.size, height: icon.size))
            }
            context.views.iconView.contentTintColor = style.iconTintColor

            context.constraints.iconWidth.constant = icon.size
            context.constraints.iconHeight.constant = icon.size

            context.views.deviceLabel.stringValue = deviceName + "  -"
            context.views.deviceLabel.textColor = style.secondaryTextColor

            context.views.volumeLabel.stringValue = statusString
            context.views.volumeLabel.textColor = style.primaryTextColor
            let widthPadding = VolumeGridConstants.HUD.Layout.volumeLabelWidthPadding
            context.constraints.volumeLabelWidth.constant = effectiveStatusTextWidth + widthPadding
            context.views.textStack.spacing = gapBetweenDeviceAndCount

            context.views.blocksView.update(style: style, fillFraction: displayedScalar)
            context.views.blocksView.isHidden = isUnsupported
            let blocksWidth =
                isUnsupported ? 0 : context.views.blocksView.intrinsicContentSize.width
            context.constraints.blocksWidth.constant = blocksWidth

            context.contentStack.setCustomSpacing(spacingIconToDevice, after: context.iconContainer)
            context.contentStack.setCustomSpacing(
                spacingDeviceToBlocks, after: context.views.textStack)

            if !isAlreadyVisible {
                hudWindow.alphaValue = 0
                hudWindow.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = VolumeGridConstants.HUD.fadeInDuration
                        hudWindow.animator().alphaValue = VolumeGridConstants.HUD.alpha
                    }, completionHandler: nil)
            } else {
                hudWindow.orderFrontRegardless()
                hudWindow.alphaValue = VolumeGridConstants.HUD.alpha
            }
        }

        if hideHUDTask != nil {
            logger.debug("Cancelling previous hideHUDTask")
        }
        hideHUDTask?.cancel()

        let task = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(VolumeGridConstants.HUD.displayDuration * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            for (_, context) in self.hudWindows {
                let hudWindow = context.window
                let shouldHideWindowWhen: () -> Bool = { [weak self] in
                    // Only hide window if this cycle is still current
                    if let self = self {
                        return cycleID == self.currentHUDCycleID
                    }
                    return true  // If manager is deallocated, allow hiding
                }

                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = VolumeGridConstants.HUD.fadeOutDuration
                        hudWindow.animator().alphaValue = 0
                    },
                    completionHandler: {
                        if shouldHideWindowWhen() {
                            hudWindow.orderOut(nil)
                        } else {
                            logger.debug(
                                "HUD cycle interrupted: suppressing orderOut (newCycleID started)"
                            )
                        }
                    })
            }
        }
        hideHUDTask = task
    }

    private static let defaultHUDStyle = HUDStyle(
        shadowColor: NSColor.white.withAlphaComponent(0.9),
        iconTintColor: NSColor.white.withAlphaComponent(0.9),
        primaryTextColor: NSColor.white.withAlphaComponent(0.9),
        secondaryTextColor: NSColor.white.withAlphaComponent(0.9),
        blockFillColor: NSColor.white.withAlphaComponent(0.9)
    )

    private func hudStyle() -> HUDStyle {
        Self.defaultHUDStyle
    }
}
