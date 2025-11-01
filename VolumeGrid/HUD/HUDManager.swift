import Cocoa
import Combine
import SwiftUI

struct HUDStyle {
    let backgroundColor: NSColor
    let shadowColor: NSColor
    let iconTintColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let blockFillColor: NSColor
    let blockEmptyColor: NSColor
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
    private let hudWidth: CGFloat = 320
    private let hudHeight: CGFloat = 160
    private let hudAlpha: CGFloat = 0.97
    private let hudDisplayDuration: TimeInterval = 2.0
    private let hudCornerRadius: CGFloat = 12
    private let marginX: CGFloat = 24
    private let minVerticalPadding: CGFloat = 14
    private let animationDuration: TimeInterval = 0.2

    private var hudWindows: [CGDirectDisplayID: HUDWindowContext] = [:]
    private var hideHUDWorkItem: DispatchWorkItem?
    private var screenChangeCancellable: AnyCancellable?

    init() {
        syncHUDWindowsWithScreens()
        screenChangeCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncHUDWindowsWithScreens()
            }
    }

    deinit {
        hideHUDWorkItem?.cancel()
        screenChangeCancellable?.cancel()
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    private func makeHUDWindow(for screen: NSScreen, screenID: CGDirectDisplayID)
        -> HUDWindowContext
    {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: hudWidth, height: hudHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .ignoresCycle,
        ]
        window.ignoresMouseEvents = true

        let containerView = NSView(
            frame: .init(x: 0, y: 0, width: hudWidth, height: hudHeight))
        containerView.wantsLayer = true
        let style = hudStyle(for: window.effectiveAppearance)
        containerView.layer?.backgroundColor = style.backgroundColor.cgColor
        containerView.layer?.cornerRadius = hudCornerRadius
        containerView.layer?.masksToBounds = true
        containerView.layer?.shadowColor = style.shadowColor.cgColor
        containerView.layer?.shadowOpacity = 1.0
        containerView.layer?.shadowOffset = .init(width: 0, height: 2)
        containerView.layer?.shadowRadius = 8
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
                greaterThanOrEqualTo: containerView.leadingAnchor, constant: marginX),
            contentStack.trailingAnchor.constraint(
                lessThanOrEqualTo: containerView.trailingAnchor, constant: -marginX),
        ])
        let topConstraint = contentStack.topAnchor.constraint(
            greaterThanOrEqualTo: containerView.topAnchor, constant: minVerticalPadding)
        topConstraint.priority = .defaultHigh
        topConstraint.isActive = true
        let bottomConstraint = contentStack.bottomAnchor.constraint(
            lessThanOrEqualTo: containerView.bottomAnchor, constant: -minVerticalPadding)
        bottomConstraint.priority = .defaultHigh
        bottomConstraint.isActive = true

        let iconContainerSize: CGFloat = 40
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
        textStack.spacing = 8

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

        let spacingIconToDevice: CGFloat = 14
        let spacingDeviceToBlocks: CGFloat = 20
        contentStack.setCustomSpacing(spacingIconToDevice, after: iconContainer)
        contentStack.setCustomSpacing(spacingDeviceToBlocks, after: textStack)

        let screenFrame = screen.frame
        let windowOrigin = CGPoint(
            x: screenFrame.midX - hudWidth / 2,
            y: screenFrame.midY - hudHeight / 2
        )
        window.setFrameOrigin(windowOrigin)
        window.alphaValue = hudAlpha

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

    private func syncHUDWindowsWithScreens() {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.syncHUDWindowsWithScreens()
            }
            return
        }

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
            context.window.orderOut(nil)
            context.window.contentView = nil
        }

        hudWindows = updated
    }

    private func calculateHUDWidth(
        deviceName: String,
        statusString: String
    ) -> (width: CGFloat, statusTextWidth: CGFloat) {
        let deviceNSString = NSString(string: deviceName + "  -")
        let font = NSFont.systemFont(ofSize: 12)
        let deviceTextSize = deviceNSString.size(withAttributes: [.font: font])

        let statusNSString = NSString(string: statusString)
        let statusTextSize = statusNSString.size(withAttributes: [.font: font])
        let maxVolumeSampleString = VolumeFormatter.formatVolumeCount(quarterBlocks: 15.75)
        let maxVolumeSampleWidth = NSString(string: maxVolumeSampleString)
            .size(withAttributes: [.font: font]).width
        let effectiveStatusTextWidth = max(statusTextSize.width, maxVolumeSampleWidth)

        let gapBetweenDeviceAndCount: CGFloat = 8
        let combinedWidth =
            deviceTextSize.width + gapBetweenDeviceAndCount + effectiveStatusTextWidth
        let marginX: CGFloat = 24
        let dynamicHudWidth = max(320, combinedWidth + 2 * marginX)

        return (dynamicHudWidth, effectiveStatusTextWidth)
    }

    func showHUD(
        volumeScalar: CGFloat, deviceName: String?, isMuted: Bool, isUnsupported: Bool = false
    ) {
        let clampedScalar = volumeScalar.clamped(to: 0...1)
        let isMutedForDisplay = isMuted || clampedScalar <= volumeEpsilon
        let displayedScalar = isMutedForDisplay ? 0 : clampedScalar

        let spacingIconToDevice: CGFloat = isUnsupported ? 20 : 14
        let spacingDeviceToBlocks: CGFloat = isUnsupported ? 0 : 20

        let deviceName = deviceName ?? "Unknown Device"
        let statusString =
            isUnsupported
            ? "Not Supported"
            : VolumeFormatter.formattedVolumeString(forScalar: displayedScalar)

        let (dynamicHudWidth, effectiveStatusTextWidth) = calculateHUDWidth(
            deviceName: deviceName,
            statusString: statusString
        )
        let gapBetweenDeviceAndCount: CGFloat = 8

        syncHUDWindowsWithScreens()

        for screen in NSScreen.screens {
            guard
                let screenID = screenID(for: screen),
                let context = hudWindows[screenID]
            else { continue }

            let hudWindow = context.window
            let isAlreadyVisible = hudWindow.isVisible && hudWindow.alphaValue > 0.1

            let style = hudStyle(for: hudWindow.effectiveAppearance)

            let screenFrame = screen.frame
            let newWindowFrame = NSRect(
                x: screenFrame.midX - dynamicHudWidth / 2,
                y: screenFrame.midY - hudHeight / 2,
                width: dynamicHudWidth,
                height: hudHeight
            )
            hudWindow.setFrame(newWindowFrame, display: true)

            let containerView = context.containerView
            containerView.frame = .init(x: 0, y: 0, width: dynamicHudWidth, height: hudHeight)
            containerView.layer?.backgroundColor = style.backgroundColor.cgColor
            containerView.layer?.shadowColor = style.shadowColor.cgColor
            containerView.layer?.shadowOpacity = 1.0

            let volumePercentage = Int(clampedScalar * 100)
            let icon = VolumeIconHelper.hudIcon(
                for: volumePercentage,
                isMuted: isMutedForDisplay,
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
            let widthPadding: CGFloat = 6
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
                        context.duration = self.animationDuration
                        hudWindow.animator().alphaValue = self.hudAlpha
                    }, completionHandler: nil)
            } else {
                hudWindow.orderFrontRegardless()
                hudWindow.alphaValue = self.hudAlpha
            }
        }

        hideHUDWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            for (_, context) in self.hudWindows {
                let hudWindow = context.window
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = self.animationDuration
                        hudWindow.animator().alphaValue = 0
                    },
                    completionHandler: {
                        hudWindow.orderOut(nil)
                    })
            }
        }
        hideHUDWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hudDisplayDuration, execute: workItem)
    }

    private func hudStyle(for appearance: NSAppearance) -> HUDStyle {
        let bestMatch = appearance.bestMatch(
            from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        let isDarkInterface = bestMatch == .darkAqua || bestMatch == .vibrantDark

        let backgroundBase = resolveColor(NSColor.windowBackgroundColor, for: appearance)
        let backgroundColor = backgroundBase.withAlphaComponent(isDarkInterface ? 0.92 : 0.97)
        let shadowColor = NSColor.black.withAlphaComponent(isDarkInterface ? 0.6 : 0.25)
        let iconTintColor = resolveColor(NSColor.labelColor, for: appearance)
        let primaryTextColor = resolveColor(NSColor.labelColor, for: appearance)
        let secondaryTextColor = resolveColor(NSColor.secondaryLabelColor, for: appearance)
        let neutralFillBase = resolveColor(NSColor.systemGray, for: appearance)
        let blockFillColor = neutralFillBase.withAlphaComponent(isDarkInterface ? 0.99 : 1.0)
        let blockEmptyColor =
            isDarkInterface
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.black.withAlphaComponent(0.12)

        return HUDStyle(
            backgroundColor: backgroundColor,
            shadowColor: shadowColor,
            iconTintColor: iconTintColor,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            blockFillColor: blockFillColor,
            blockEmptyColor: blockEmptyColor
        )
    }

    private func resolveColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.extendedSRGB) ?? color
        }
        return resolved
    }
}
