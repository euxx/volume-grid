import Cocoa
import SwiftUI

// Manages HUD window display and animation
class HUDManager {
    private var hudWindows: [CGDirectDisplayID: HUDWindowContext] = [:]
    private var hideHUDWorkItem: DispatchWorkItem?
    private var screenChangeObserver: NSObjectProtocol?

    // HUD constants.
    private let hudWidth: CGFloat = 320
    private let hudHeight: CGFloat = 160
    private let hudAlpha: CGFloat = 0.97
    private let hudDisplayDuration: TimeInterval = 2.0

    init() {
        syncHUDWindowsWithScreens()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncHUDWindowsWithScreens()
        }
    }

    deinit {
        hideHUDWorkItem?.cancel()
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber
        {
            return CGDirectDisplayID(number.uint32Value)
        }
        return nil
    }

    private func makeHUDWindow(for screen: NSScreen, screenID: CGDirectDisplayID)
        -> HUDWindowContext
    {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight),
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
            frame: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight))
        containerView.wantsLayer = true
        let style = hudStyle(for: window.effectiveAppearance)
        containerView.layer?.backgroundColor = style.backgroundColor.cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        containerView.layer?.shadowColor = style.shadowColor.cgColor
        containerView.layer?.shadowOpacity = 1.0
        containerView.layer?.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer?.shadowRadius = 8
        window.contentView = containerView

        let contentStack = NSStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 0
        containerView.addSubview(contentStack)

        let marginX: CGFloat = 24
        let minVerticalPadding: CGFloat = 14
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
            x: screenFrame.origin.x + (screenFrame.width - hudWidth) / 2,
            y: screenFrame.origin.y + (screenFrame.height - hudHeight) / 2
        )
        window.setFrameOrigin(windowOrigin)
        window.alphaValue = hudAlpha

        return HUDWindowContext(
            screenID: screenID,
            window: window,
            containerView: containerView,
            contentStack: contentStack,
            iconContainer: iconContainer,
            iconView: iconView,
            textStack: textStack,
            deviceLabel: deviceLabel,
            volumeLabel: volumeLabel,
            blocksView: blocksView
        )
    }

    private func syncHUDWindowsWithScreens() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
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
        }

        hudWindows = updated
    }

    func showHUD(
        volumeScalar: CGFloat, deviceName: String?, isMuted: Bool, isUnsupported: Bool = false
    ) {
        let clampedScalar = max(0, min(volumeScalar, 1))
        let epsilon: CGFloat = 0.001
        let isMutedForDisplay = isMuted || clampedScalar <= epsilon
        let displayedScalar = isMutedForDisplay ? 0 : clampedScalar

        let deviceName = deviceName ?? "Unknown Device"
        let deviceNSString = NSString(string: deviceName + "  -")
        let deviceFont = NSFont.systemFont(ofSize: 12)
        let deviceTextSize = deviceNSString.size(withAttributes: [.font: deviceFont])
        let statusString =
            isUnsupported
            ? "Not Supported"
            : VolumeFormatter.formattedVolumeString(forScalar: displayedScalar)
        let statusNSString = NSString(string: statusString)
        let statusFont = NSFont.systemFont(ofSize: 12)
        let statusTextSize = statusNSString.size(withAttributes: [.font: statusFont])
        let maxVolumeSampleString = VolumeFormatter.formatVolumeCount(quarterBlocks: 15.75)
        let maxVolumeSampleWidth = NSString(string: maxVolumeSampleString).size(withAttributes: [
            .font: statusFont
        ]).width
        let effectiveStatusTextWidth = max(statusTextSize.width, maxVolumeSampleWidth)
        let gapBetweenDeviceAndCount: CGFloat = 8
        let combinedWidth =
            deviceTextSize.width + gapBetweenDeviceAndCount + effectiveStatusTextWidth
        let marginX: CGFloat = 24
        let dynamicHudWidth = max(320, combinedWidth + 2 * marginX)

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
                x: screenFrame.origin.x + (screenFrame.width - dynamicHudWidth) / 2,
                y: screenFrame.origin.y + (screenFrame.height - hudHeight) / 2,
                width: dynamicHudWidth,
                height: hudHeight
            )
            hudWindow.setFrame(newWindowFrame, display: true)

            let containerView = context.containerView
            containerView.frame = NSRect(x: 0, y: 0, width: dynamicHudWidth, height: hudHeight)
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
                context.iconView.image = speakerImage
            } else if let fallbackImage = NSImage(
                named: NSImage.touchBarAudioOutputVolumeHighTemplateName)
            {
                context.iconView.image = fallbackImage
            } else {
                context.iconView.image = NSImage(size: NSSize(width: icon.size, height: icon.size))
            }
            context.iconView.contentTintColor = style.iconTintColor

            // Update icon size via constraints
            for constraint in context.iconView.constraints {
                if constraint.firstAttribute == .width || constraint.secondAttribute == .width {
                    constraint.constant = icon.size
                } else if constraint.firstAttribute == .height
                    || constraint.secondAttribute == .height
                {
                    constraint.constant = icon.size
                }
            }

            context.deviceLabel.stringValue = deviceName + "  -"
            context.deviceLabel.textColor = style.secondaryTextColor

            context.volumeLabel.stringValue = statusString
            context.volumeLabel.textColor = style.primaryTextColor
            let widthPadding: CGFloat = 6
            for constraint in context.volumeLabel.constraints {
                if constraint.firstAttribute == .width || constraint.secondAttribute == .width {
                    constraint.constant = effectiveStatusTextWidth + widthPadding
                    break
                }
            }
            context.textStack.spacing = gapBetweenDeviceAndCount

            context.blocksView.update(style: style, fillFraction: displayedScalar)
            if isUnsupported {
                context.blocksView.isHidden = true
                for constraint in context.blocksView.constraints {
                    if constraint.firstAttribute == .width || constraint.secondAttribute == .width {
                        constraint.constant = 0
                        break
                    }
                }
            } else {
                context.blocksView.isHidden = false
                for constraint in context.blocksView.constraints {
                    if constraint.firstAttribute == .width || constraint.secondAttribute == .width {
                        constraint.constant = context.blocksView.intrinsicContentSize.width
                        break
                    }
                }
            }

            let spacingIconToDevice: CGFloat = isUnsupported ? 20 : 14
            let spacingDeviceToBlocks: CGFloat = isUnsupported ? 0 : 20
            context.contentStack.setCustomSpacing(spacingIconToDevice, after: context.iconContainer)
            context.contentStack.setCustomSpacing(spacingDeviceToBlocks, after: context.textStack)

            if !isAlreadyVisible {
                hudWindow.alphaValue = 0
                hudWindow.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = 0.2
                        hudWindow.animator().alphaValue = self.hudAlpha
                    }, completionHandler: nil)
            } else {
                hudWindow.orderFrontRegardless()
                hudWindow.alphaValue = self.hudAlpha
            }
        }

        hideHUDWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            for (_, context) in self.hudWindows {
                let hudWindow = context.window
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = 0.2
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
        let bestMatch =
            appearance.bestMatch(from: [
                .darkAqua,
                .vibrantDark,
                .aqua,
                .vibrantLight,
            ]) ?? .aqua
        let isDarkInterface = (bestMatch == .darkAqua || bestMatch == .vibrantDark)

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
