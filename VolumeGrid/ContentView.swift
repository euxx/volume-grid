import SwiftUI
import Combine
import Cocoa
import AudioToolbox

// 音频设备结构体
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

// SwiftUI 视图
struct ContentView: View {
    @EnvironmentObject private var volumeMonitor: VolumeMonitor

    var body: some View {
        VStack {
            Image(systemName: "speaker.wave.2.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("VolumeGrid")
                .font(.headline)
            Text("当前音量: \(volumeMonitor.volumePercentage)%")
                .font(.title2)
                .padding()

            // 显示当前设备
            if let currentDevice = volumeMonitor.currentDevice {
                Text("当前设备: \(currentDevice.name)")
                    .font(.subheadline)
                    .padding(.bottom, 10)
            }
        }
        .padding()
        .onAppear {
            volumeMonitor.startListening()
            volumeMonitor.getAudioDevices()
        }
        .onDisappear {
            volumeMonitor.stopListening()
        }
    }
}

// VolumeMonitor 类
class VolumeMonitor: ObservableObject {
    @Published var volumePercentage: Int = 0
    @Published var audioDevices: [AudioDevice] = []
    @Published var currentDevice: AudioDevice?
    private var defaultOutputDeviceID: AudioDeviceID = 0
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var hudWindows: [NSWindow] = []
    private var audioQueue: DispatchQueue?
    private var hideHUDWorkItem: DispatchWorkItem?
    private var volumeElements: [AudioObjectPropertyElement] = []
    private var muteElements: [AudioObjectPropertyElement] = []
    private var lastVolumeScalar: CGFloat?
    private var isDeviceMuted: Bool = false
    private var globalSystemEventMonitor: Any?
    private var localSystemEventMonitor: Any?
    private var lastHandledSystemEvent: (timestamp: TimeInterval, data: Int)?
    private var muteListener: AudioObjectPropertyListenerBlock?

    // HUD 常量
    private let hudWidth: CGFloat = 320
    private let hudHeight: CGFloat = 160
    private let hudAlpha: CGFloat = 0.97
    private let hudDisplayDuration: TimeInterval = 2.0
    private let hudFontSize: CGFloat = 24

    private struct HUDStyle {
        let backgroundColor: NSColor
        let shadowColor: NSColor
        let iconTintColor: NSColor
        let primaryTextColor: NSColor
        let secondaryTextColor: NSColor
        let blockFillColor: NSColor
        let blockEmptyColor: NSColor
    }

    private func resolveColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.extendedSRGB) ?? color
        }
        return resolved
    }

    private func hudStyle(for appearance: NSAppearance) -> HUDStyle {
        let bestMatch = appearance.bestMatch(from: [
            .darkAqua,
            .vibrantDark,
            .aqua,
            .vibrantLight
        ]) ?? .aqua
        let isDarkInterface = (bestMatch == .darkAqua || bestMatch == .vibrantDark)

        let backgroundBase = resolveColor(NSColor.windowBackgroundColor, for: appearance)
        let backgroundColor = backgroundBase.withAlphaComponent(isDarkInterface ? 0.92 : 0.97)
        let shadowColor = NSColor.black.withAlphaComponent(isDarkInterface ? 0.6 : 0.25)
        let iconTintColor = resolveColor(NSColor.labelColor, for: appearance)
        let primaryTextColor = resolveColor(NSColor.labelColor, for: appearance)
        let secondaryTextColor = resolveColor(NSColor.secondaryLabelColor, for: appearance)
        let accentColor = resolveColor(NSColor.controlAccentColor, for: appearance)
        let blockFillColor = accentColor.withAlphaComponent(isDarkInterface ? 0.9 : 1.0)
        let blockEmptyColor = isDarkInterface
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

    init() {
        // Initialize HUD window once
        setupHUDWindow()
        // Create audio queue once
        audioQueue = DispatchQueue(label: "com.volumegrid.audio", qos: .userInitiated)
        // Get initial volume
        if let volume = getCurrentVolume() {
            volumePercentage = Int(volume * 100)
            lastVolumeScalar = CGFloat(volume)
        }
        _ = refreshMuteState()
        // Get audio devices
        getAudioDevices()
    }

    deinit {
        stopListening()
        hideHUDWorkItem?.cancel()
        #if DEBUG
        print("VolumeMonitor deinit")
        #endif
    }

    // 创建音量方格视图
    private func createVolumeBlocksView(fillFraction: CGFloat, style: HUDStyle) -> NSView {
        let blockCount = 16
        let blockWidth: CGFloat = 14  // 稍微增宽
        let blockHeight: CGFloat = 6  // 稍微减高，更细长
        let blockSpacing: CGFloat = 2  // 减小间距

        let totalWidth = CGFloat(blockCount) * blockWidth + CGFloat(blockCount - 1) * blockSpacing
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: blockHeight))

        let clampedFraction = max(0, min(1, fillFraction))
        let totalBlocks = clampedFraction * CGFloat(blockCount)

        for i in 0..<blockCount {
            let block = NSView(frame: NSRect(
                x: CGFloat(i) * (blockWidth + blockSpacing),
                y: 0,
                width: blockWidth,
                height: blockHeight
            ))

            block.wantsLayer = true
            block.layer?.cornerRadius = 0.5  // 更小的圆角，更精致
            block.layer?.backgroundColor = style.blockEmptyColor.cgColor

            var blockFill = totalBlocks - CGFloat(i)
            blockFill = max(0, min(1, blockFill))
            blockFill = (blockFill * 4).rounded() / 4  // 最小支持 1/4 单位

            if blockFill > 0 {
                let fillLayer = CALayer()
                fillLayer.backgroundColor = style.blockFillColor.cgColor
                fillLayer.cornerRadius = 0.5
                fillLayer.frame = CGRect(x: 0, y: 0, width: blockWidth * blockFill, height: blockHeight)
                block.layer?.addSublayer(fillLayer)
            }

            containerView.addSubview(block)
        }

        return containerView
    }

    // 设置 HUD 窗口
    private func setupHUDWindow() {
        hudWindows = NSScreen.screens.map { screen in
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
                .ignoresCycle
            ]
            window.ignoresMouseEvents = true

            // 创建容器视图，添加Mac风格的背景
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight))
            containerView.wantsLayer = true
            let style = hudStyle(for: window.effectiveAppearance)
            containerView.layer?.backgroundColor = style.backgroundColor.cgColor
            containerView.layer?.cornerRadius = 12
            containerView.layer?.masksToBounds = true

            // 添加轻微的阴影效果
            containerView.layer?.shadowColor = style.shadowColor.cgColor
            containerView.layer?.shadowOpacity = 1.0
            containerView.layer?.shadowOffset = CGSize(width: 0, height: 2)
            containerView.layer?.shadowRadius = 8

            window.contentView = containerView

            // 设置窗口在对应屏幕的中心
            let screenFrame = screen.frame
            let windowOrigin = CGPoint(
                x: screenFrame.origin.x + (screenFrame.width - hudWidth) / 2,
                y: screenFrame.origin.y + (screenFrame.height - hudHeight) / 2
            )
            window.setFrameOrigin(windowOrigin)

            // 设置初始透明度
            window.alphaValue = self.hudAlpha

            return window
        }
    }

    // 获取默认输出设备 ID
    @discardableResult
    private func updateDefaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        if status == noErr {
            self.defaultOutputDeviceID = deviceID
            #if DEBUG
            print("Updated default device ID: \(deviceID)")
            #endif
            return deviceID
        } else {
            #if DEBUG
            print("Error getting default output device: \(status)")
            #endif
            return 0
        }
    }

    // 更新可用的音量通道（优先主通道，其次左右声道）
    @discardableResult
    private func updateVolumeElements(for deviceID: AudioDeviceID) -> Bool {
        let candidates: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2
        ]

        var detected: [AudioObjectPropertyElement] = []

        for element in candidates {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            if AudioObjectHasProperty(deviceID, &address) {
                if element == kAudioObjectPropertyElementMain {
                    volumeElements = [element]
                    return true
                }
                detected.append(element)
            }
        }

        if !detected.isEmpty {
            volumeElements = detected
            return true
        }

        volumeElements = []
        return false
    }

    @discardableResult
    private func updateMuteElements(for deviceID: AudioDeviceID) -> Bool {
        let candidates: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2
        ]

        var detected: [AudioObjectPropertyElement] = []

        for element in candidates {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            if AudioObjectHasProperty(deviceID, &address) {
                if element == kAudioObjectPropertyElementMain {
                    muteElements = [element]
                    return true
                }
                detected.append(element)
            }
        }

        if !detected.isEmpty {
            muteElements = detected
            return true
        }

        muteElements = []
        return false
    }

    private func deviceSupportsMute(_ deviceID: AudioDeviceID) -> Bool {
        return updateMuteElements(for: deviceID)
    }

    // 检查设备是否支持音量控制
    private func deviceSupportsVolumeControl(_ deviceID: AudioDeviceID) -> Bool {
        return updateVolumeElements(for: deviceID)
    }

    // 获取当前音量
    func getCurrentVolume() -> Float32? {
        let deviceID = updateDefaultOutputDevice()
        guard deviceID != 0 else { return nil }

        guard deviceSupportsVolumeControl(deviceID) else {
            #if DEBUG
            print("Device does not support volume control")
            #endif
            return nil
        }

        let elements = volumeElements
        guard !elements.isEmpty else { return nil }

        var channelVolumes: [Float32] = []

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            var volume: Float32 = 0.0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)

            if status == noErr {
                channelVolumes.append(volume)
            } else {
                #if DEBUG
                print("Error getting volume for element \(element): \(status)")
                #endif
            }
        }

        guard !channelVolumes.isEmpty else { return nil }

        let total = channelVolumes.reduce(0, +)
        return total / Float32(channelVolumes.count)
    }

    // 获取音频设备列表
    func getAudioDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            #if DEBUG
            print("Error getting devices size: \(status)")
            #endif
            return
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else {
            #if DEBUG
            print("Error getting devices: \(status)")
            #endif
            return
        }

        var devices: [AudioDevice] = []
        for deviceID in deviceIDs {
            if let name = getDeviceName(deviceID) {
                devices.append(AudioDevice(id: deviceID, name: name))
            }
        }

        DispatchQueue.main.async {
            self.audioDevices = devices
            // 设置当前设备
            let currentID = self.defaultOutputDeviceID != 0 ? self.defaultOutputDeviceID : self.updateDefaultOutputDevice()
            if currentID != 0, let currentDevice = devices.first(where: { $0.id == currentID }) {
                self.currentDevice = currentDevice
            }
        }
    }

    // 获取设备名称
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanaged = unmanagedName else {
            #if DEBUG
            print("Error getting device name for \(deviceID): \(status)")
            #endif
            return nil
        }
        let name = unmanaged.takeRetainedValue() as String
        return name
    }

    @discardableResult
    private func refreshMuteState(for deviceID: AudioDeviceID? = nil) -> Bool? {
        if !Thread.isMainThread {
            var result: Bool?
            DispatchQueue.main.sync {
                result = self.refreshMuteState(for: deviceID)
            }
            return result
        }

        let resolvedDeviceID: AudioDeviceID
        if let deviceID {
            resolvedDeviceID = deviceID
        } else {
            let currentID = defaultOutputDeviceID != 0 ? defaultOutputDeviceID : updateDefaultOutputDevice()
            guard currentID != 0 else {
                isDeviceMuted = false
                return nil
            }
            resolvedDeviceID = currentID
        }

        guard !muteElements.isEmpty || deviceSupportsMute(resolvedDeviceID) else {
            isDeviceMuted = false
            return nil
        }

        var muteDetected = false
        var readAnyMuteChannel = false

        for element in muteElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(resolvedDeviceID, &address, 0, nil, &size, &muted)
            if status == noErr {
                readAnyMuteChannel = true
                if muted != 0 {
                    muteDetected = true
                    break
                }
            } else {
                #if DEBUG
                print("Error getting mute for element \(element): \(status)")
                #endif
            }
        }

        guard readAnyMuteChannel else {
            #if DEBUG
            print("No mute channels returned data")
            #endif
            isDeviceMuted = false
            return nil
        }

        isDeviceMuted = muteDetected
        if muteDetected {
            volumePercentage = 0
        }
        return muteDetected
    }

    // 音量变化回调
    private func volumeChanged(address _: AudioObjectPropertyAddress) {
        guard let volume = getCurrentVolume() else {
            #if DEBUG
            print("Failed to read volume after change")
            #endif
            return
        }

        let clampedVolume = max(0, min(volume, 1))
        let percentage = Int(round(clampedVolume * 100))
        DispatchQueue.main.async {
            let previousScalar = self.lastVolumeScalar
            let currentScalar = CGFloat(clampedVolume)
            self.lastVolumeScalar = currentScalar
            self.volumePercentage = percentage
            let epsilon: CGFloat = 0.001
            var shouldShowHUD = false
            if let previousScalar {
                // 忽略未造成实际音量变化的事件（例如系统通知带来的虚假回调）
                shouldShowHUD = abs(previousScalar - currentScalar) > epsilon
                if !shouldShowHUD {
                    // 在边界值（0 或最大音量）时，仍然响应用户的重复按键
                    let isAtLowerBound = previousScalar <= epsilon && currentScalar <= epsilon
                    let isAtUpperBound = previousScalar >= (1 - epsilon) && currentScalar >= (1 - epsilon)
                    if isAtLowerBound || isAtUpperBound {
                        shouldShowHUD = true
                    }
                }
            } else {
                shouldShowHUD = true
            }
            if currentScalar > epsilon, self.isDeviceMuted {
                self.isDeviceMuted = false
            }
            if shouldShowHUD {
                self.showVolumeHUD(volumeScalar: currentScalar)
            }
            #if DEBUG
            print("Volume changed: \(percentage)%")
            #endif
        }
    }

    private func muteChanged(address _: AudioObjectPropertyAddress) {
        DispatchQueue.main.async {
            self.showHUDForCurrentVolume()
        }
    }

    // 默认设备变化回调
    private func deviceChanged() {
        stopListening()
        updateDefaultOutputDevice()
        getAudioDevices()
        startListening()

        // Refresh the current device immediately so the HUD reflects the new selection.
        if defaultOutputDeviceID != 0 {
            if let current = audioDevices.first(where: { $0.id == defaultOutputDeviceID }) {
                currentDevice = current
            } else if let name = getDeviceName(defaultOutputDeviceID) {
                currentDevice = AudioDevice(id: defaultOutputDeviceID, name: name)
            } else {
                currentDevice = nil
            }
        } else {
            currentDevice = nil
        }

        _ = refreshMuteState()
        if let volume = getCurrentVolume() {
            let clampedVolume = max(0, min(volume, 1))
            let percentage = Int(round(clampedVolume * 100))
            self.volumePercentage = percentage
            self.lastVolumeScalar = CGFloat(clampedVolume)
            self.showVolumeHUD(volumeScalar: CGFloat(clampedVolume))
            #if DEBUG
            print("Device switched, new volume: \(percentage)%")
            #endif
        }
    }

    // 显示音量 HUD
    private func showVolumeHUD(volumeScalar: CGFloat) {
        let clampedScalar = max(0, min(volumeScalar, 1))
        let epsilon: CGFloat = 0.001
        let isMutedForDisplay = isDeviceMuted || clampedScalar <= epsilon
        let displayedScalar = isMutedForDisplay ? 0 : clampedScalar
        let totalBlocks = displayedScalar * 16.0
        let quarterBlocks = (totalBlocks * 4).rounded() / 4
        let formattedQuarterBlocks = formatVolumeCount(quarterBlocks)
        let volumeString: String
        if formattedQuarterBlocks.contains("/") {
            let normalizedNumerator = formattedQuarterBlocks.replacingOccurrences(of: " ", with: "+")
            volumeString = normalizedNumerator
        } else {
            volumeString = formattedQuarterBlocks
        }

        // 预计算文本宽度以调整窗口大小
        let deviceName = currentDevice?.name ?? "未知设备"
        let deviceNSString = NSString(string: deviceName + "  -")
        let deviceFont = NSFont.systemFont(ofSize: 12)
        let deviceTextSize = deviceNSString.size(withAttributes: [.font: deviceFont])
        let volumeNSString = NSString(string: volumeString)
        let volumeFont = NSFont.systemFont(ofSize: 12)
        let volumeTextSize = volumeNSString.size(withAttributes: [.font: volumeFont])
        let maxVolumeSampleString = "15+3/4"
        let maxVolumeSampleWidth = NSString(string: maxVolumeSampleString).size(withAttributes: [.font: volumeFont]).width
        let effectiveVolumeTextWidth = max(volumeTextSize.width, maxVolumeSampleWidth)
        let gapBetweenDeviceAndCount: CGFloat = 8
        let combinedWidth = deviceTextSize.width + gapBetweenDeviceAndCount + effectiveVolumeTextWidth
        let marginX: CGFloat = 24
        let dynamicHudWidth = max(320, combinedWidth + 2 * marginX)  // 最小320，确保文本不被裁剪

        for hudWindow in hudWindows {
            // 检查窗口是否已经显示
            let isAlreadyVisible = hudWindow.isVisible && hudWindow.alphaValue > 0.1

            let style = hudStyle(for: hudWindow.effectiveAppearance)

            // 调整窗口宽度以适应内容
            let screenFrame = NSScreen.screens[hudWindows.firstIndex(of: hudWindow)!].frame
            let newWindowFrame = NSRect(
                x: screenFrame.origin.x + (screenFrame.width - dynamicHudWidth) / 2,
                y: screenFrame.origin.y + (screenFrame.height - hudHeight) / 2,
                width: dynamicHudWidth,
                height: hudHeight
            )
            hudWindow.setFrame(newWindowFrame, display: true)

            guard let containerView = hudWindow.contentView else { continue }

            // 清空之前的内容
            containerView.subviews.forEach { $0.removeFromSuperview() }

            // 调整容器视图大小
            containerView.frame = NSRect(x: 0, y: 0, width: dynamicHudWidth, height: hudHeight)
            containerView.layer?.backgroundColor = style.backgroundColor.cgColor
            containerView.layer?.shadowColor = style.shadowColor.cgColor
            containerView.layer?.shadowOpacity = 1.0

            // 创建音量图标容器
            let iconContainerSize: CGFloat = 40
            let iconContainer = NSView()
            iconContainer.translatesAutoresizingMaskIntoConstraints = false

            // 创建音量图标
            let iconName = isMutedForDisplay ? "speaker.slash.fill" : "speaker.wave.2.fill"
            let speakerImage = NSImage(systemSymbolName: iconName, accessibilityDescription: "Volume")
            let speakerImageView = NSImageView(image: speakerImage!)
            // 图标在容器内居中显示，使用原始大小
            let iconSize: CGFloat = isMutedForDisplay ? 40 : 47
            speakerImageView.imageScaling = .scaleProportionallyUpOrDown
            speakerImageView.contentTintColor = style.iconTintColor

            speakerImageView.translatesAutoresizingMaskIntoConstraints = false
            // 将图标添加到容器中
            iconContainer.addSubview(speakerImageView)
            NSLayoutConstraint.activate([
                speakerImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                speakerImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
                speakerImageView.widthAnchor.constraint(equalToConstant: iconSize),
                speakerImageView.heightAnchor.constraint(equalToConstant: iconSize)
            ])

            // 创建音量方格视图
            let blocksView = createVolumeBlocksView(fillFraction: displayedScalar, style: style)
            let blocksSize = blocksView.frame.size
            blocksView.translatesAutoresizingMaskIntoConstraints = false

            // 创建设备名称标签
            let deviceLabel = NSTextField(labelWithString: deviceName + "  -")
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

            // 创建音量格数标签
            let volumeText = NSTextField(labelWithString: volumeString)
            volumeText.translatesAutoresizingMaskIntoConstraints = false
            volumeText.textColor = style.primaryTextColor
            volumeText.font = .systemFont(ofSize: 12, weight: .regular)
            volumeText.alignment = .left
            volumeText.isBordered = false
            volumeText.backgroundColor = .clear
            volumeText.isEditable = false
            volumeText.isSelectable = false
            volumeText.lineBreakMode = .byClipping
            volumeText.setContentHuggingPriority(.required, for: .horizontal)
            volumeText.setContentCompressionResistancePriority(.required, for: .horizontal)
            let widthPadding: CGFloat = 6
            let volumeWidthConstraint = volumeText.widthAnchor.constraint(equalToConstant: effectiveVolumeTextWidth + widthPadding)
            volumeWidthConstraint.priority = .required
            volumeWidthConstraint.isActive = true

            // 使用 StackView 保证垂直居中和等距
            let contentStack = NSStackView()
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentStack.orientation = .vertical
            contentStack.alignment = .centerX
            contentStack.spacing = 0

            containerView.addSubview(contentStack)

            let minVerticalPadding: CGFloat = 14
            NSLayoutConstraint.activate([
                contentStack.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                contentStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: marginX),
                contentStack.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -marginX)
            ])

            let topConstraint = contentStack.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: minVerticalPadding)
            topConstraint.priority = .defaultHigh
            topConstraint.isActive = true

            let bottomConstraint = contentStack.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -minVerticalPadding)
            bottomConstraint.priority = .defaultHigh
            bottomConstraint.isActive = true

            contentStack.addArrangedSubview(iconContainer)
            NSLayoutConstraint.activate([
                iconContainer.widthAnchor.constraint(equalToConstant: iconContainerSize),
                iconContainer.heightAnchor.constraint(equalToConstant: iconContainerSize)
            ])

            let textStack = NSStackView()
            textStack.translatesAutoresizingMaskIntoConstraints = false
            textStack.orientation = .horizontal
            textStack.alignment = .firstBaseline
            textStack.spacing = gapBetweenDeviceAndCount
            textStack.addArrangedSubview(deviceLabel)
            textStack.addArrangedSubview(volumeText)
            contentStack.addArrangedSubview(textStack)

            let spacingIconToDevice: CGFloat = 10
            let spacingDeviceToBlocks: CGFloat = 20
            contentStack.setCustomSpacing(spacingIconToDevice, after: iconContainer)
            contentStack.setCustomSpacing(spacingDeviceToBlocks, after: textStack)

            contentStack.addArrangedSubview(blocksView)
            NSLayoutConstraint.activate([
                blocksView.widthAnchor.constraint(equalToConstant: blocksSize.width),
                blocksView.heightAnchor.constraint(equalToConstant: blocksSize.height)
            ])

            // 只在窗口未显示时执行淡入动画
            if !isAlreadyVisible {
                hudWindow.alphaValue = 0
                hudWindow.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    hudWindow.animator().alphaValue = self.hudAlpha
                }, completionHandler: nil)
            } else {
                hudWindow.orderFrontRegardless()
                // 窗口已经显示，保持当前透明度
                hudWindow.alphaValue = self.hudAlpha
            }
        }

        // 取消之前的隐藏任务
        hideHUDWorkItem?.cancel()

        // 创建新的隐藏任务
        let workItem = DispatchWorkItem {
            for hudWindow in self.hudWindows {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    hudWindow.animator().alphaValue = 0
                }, completionHandler: {
                    hudWindow.orderOut(nil)
                })
            }
        }
        hideHUDWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hudDisplayDuration, execute: workItem)
    }

    // 将 0.25、0.5、0.75 等小数格式化为 1/4、2/4、3/4
    private func formatVolumeCount(_ value: CGFloat) -> String {
        let integerPart = Int(value)
        let fractionalPart = value - CGFloat(integerPart)
        let epsilon: CGFloat = 0.001

        if fractionalPart < epsilon {
            return "\(integerPart)"
        }

        if abs(fractionalPart - 1.0) < epsilon {
            return "\(integerPart + 1)"
        }

        let fractionString: String
        switch fractionalPart {
        case (0.25 - epsilon)...(0.25 + epsilon):
            fractionString = "1/4"
        case (0.5 - epsilon)...(0.5 + epsilon):
            fractionString = "2/4"
        case (0.75 - epsilon)...(0.75 + epsilon):
            fractionString = "3/4"
        default:
            fractionString = String(format: "%.2f", fractionalPart)
        }

        if integerPart == 0 {
            return fractionString
        } else {
            return "\(integerPart) \(fractionString)"
        }
    }

    private func startKeyMonitoring() {
        if globalSystemEventMonitor == nil {
            globalSystemEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                DispatchQueue.main.async {
                    self?.handleSystemDefinedEvent(event)
                }
            }
        }

        if localSystemEventMonitor == nil {
            localSystemEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                self?.handleSystemDefinedEvent(event)
                return event
            }
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = globalSystemEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalSystemEventMonitor = nil
        }
        if let monitor = localSystemEventMonitor {
            NSEvent.removeMonitor(monitor)
            localSystemEventMonitor = nil
        }
        lastHandledSystemEvent = nil
    }

    private func handleSystemDefinedEvent(_ event: NSEvent) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleSystemDefinedEvent(event)
            }
            return
        }

        guard event.subtype.rawValue == 8 else { return }
        let keyCode = (event.data1 & 0xFFFF0000) >> 16
        let keyFlags = event.data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0xA
        guard isKeyDown else { return }

        let signature = (timestamp: event.timestamp, data: event.data1)
        if let last = lastHandledSystemEvent,
           abs(last.timestamp - signature.timestamp) < 0.0001,
           last.data == signature.data {
            return
        }
        lastHandledSystemEvent = signature

        switch keyCode & 0xFF {
        case 0, 1, 7:  // NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE
            showHUDForCurrentVolume()
        default:
            break
        }
    }

    private func showHUDForCurrentVolume() {
        _ = refreshMuteState()
        if let volume = getCurrentVolume() {
            let clamped = max(0, min(volume, 1))
            let scalar = CGFloat(clamped)
            lastVolumeScalar = scalar
            if isDeviceMuted {
                volumePercentage = 0
            } else {
                volumePercentage = Int(round(clamped * 100))
            }
            showVolumeHUD(volumeScalar: scalar)
        } else if let lastScalar = lastVolumeScalar {
            showVolumeHUD(volumeScalar: lastScalar)
        } else {
            showVolumeHUD(volumeScalar: 0)
        }
    }

    // 注册监听器
    func startListening() {
        let deviceID = updateDefaultOutputDevice()
        guard deviceID != 0 else {
            #if DEBUG
            print("No valid output device")
            #endif
            return
        }

        guard deviceSupportsVolumeControl(deviceID) else {
            #if DEBUG
            print("Device does not support volume control, skipping listener setup")
            #endif
            return
        }

        _ = deviceSupportsMute(deviceID)
        _ = refreshMuteState(for: deviceID)
        startKeyMonitoring()

        // 音量变化监听
        volumeListener = { [weak self] (_: UInt32, inAddresses: UnsafePointer<AudioObjectPropertyAddress>) in
            guard let self = self else {
                #if DEBUG
                print("VolumeMonitor deallocated in volume listener")
                #endif
                return
            }
            self.volumeChanged(address: inAddresses.pointee)
        }

        guard let audioQueue = audioQueue, let volumeListener = volumeListener else {
            #if DEBUG
            print("Failed to initialize audio queue or volume listener")
            #endif
            return
        }

        var listenerRegistered = false
        for element in volumeElements {
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            let volumeStatus = AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, audioQueue, volumeListener)
            if volumeStatus == noErr {
                listenerRegistered = true
            } else {
                #if DEBUG
                print("Error adding volume listener for element \(element): \(volumeStatus)")
                #endif
            }
        }

        guard listenerRegistered else {
            #if DEBUG
            print("Failed to register any volume listeners")
            #endif
            return
        }

        if !muteElements.isEmpty {
            muteListener = { [weak self] (_: UInt32, inAddresses: UnsafePointer<AudioObjectPropertyAddress>) in
                guard let self = self else {
                    #if DEBUG
                    print("VolumeMonitor deallocated in mute listener")
                    #endif
                    return
                }
                self.muteChanged(address: inAddresses.pointee)
            }

            if let muteListener = muteListener {
                for element in muteElements {
                    var muteAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyMute,
                        mScope: kAudioDevicePropertyScopeOutput,
                        mElement: element
                    )

                    if AudioObjectHasProperty(deviceID, &muteAddress) {
                        let muteStatus = AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, audioQueue, muteListener)
                        if muteStatus != noErr {
                            #if DEBUG
                            print("Error adding mute listener for element \(element): \(muteStatus)")
                            #endif
                        }
                    }
                }
            }
        }

        // 默认设备变化监听
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        deviceListener = { [weak self] (_: UInt32, _: UnsafePointer<AudioObjectPropertyAddress>) in
            guard let self = self else {
                #if DEBUG
                print("VolumeMonitor deallocated in device listener")
                #endif
                return
            }
            DispatchQueue.main.async {
                self.deviceChanged()
            }
        }

        guard let deviceListener = deviceListener else {
            #if DEBUG
            print("Failed to initialize device listener")
            #endif
            return
        }

        let deviceStatus = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, audioQueue, deviceListener)
        if deviceStatus != noErr {
            #if DEBUG
            print("Error adding device listener: \(deviceStatus)")
            #endif
        }
    }

    // 停止监听
    func stopListening() {
        stopKeyMonitoring()
        guard let audioQueue = audioQueue else {
            volumeListener = nil
            deviceListener = nil
            return
        }

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        if let volumeListener = volumeListener {
            for element in volumeElements {
                var volumeAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                AudioObjectRemovePropertyListenerBlock(defaultOutputDeviceID, &volumeAddress, audioQueue, volumeListener)
            }
        }

        if let muteListener = muteListener {
            for element in muteElements {
                var muteAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyMute,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                AudioObjectRemovePropertyListenerBlock(defaultOutputDeviceID, &muteAddress, audioQueue, muteListener)
            }
        }

        if let deviceListener = deviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, audioQueue, deviceListener)
        }

        self.volumeListener = nil
        self.deviceListener = nil
        self.muteListener = nil
        #if DEBUG
        print("Stopped listening")
        #endif
    }
}
