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
            Text("Sound Monitor")
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

    // HUD 常量
    private let hudWidth: CGFloat = 320
    private let hudHeight: CGFloat = 200
    private let hudAlpha: CGFloat = 0.85
    private let hudDisplayDuration: TimeInterval = 2.0
    private let hudFontSize: CGFloat = 24

    init() {
        // Initialize HUD window once
        setupHUDWindow()
        // Create audio queue once
        audioQueue = DispatchQueue(label: "com.soundmonitor.audio", qos: .userInitiated)
        // Get initial volume
        if let volume = getCurrentVolume() {
            volumePercentage = Int(volume * 100)
        }
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
    private func createVolumeBlocksView(filledBlocks: Int) -> NSView {
        let blockCount = 16
        let blockWidth: CGFloat = 14  // 稍微增宽
        let blockHeight: CGFloat = 6  // 稍微减高，更细长
        let blockSpacing: CGFloat = 2  // 减小间距

        let totalWidth = CGFloat(blockCount) * blockWidth + CGFloat(blockCount - 1) * blockSpacing
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: blockHeight))

        for i in 0..<blockCount {
            let block = NSView(frame: NSRect(
                x: CGFloat(i) * (blockWidth + blockSpacing),
                y: 0,
                width: blockWidth,
                height: blockHeight
            ))

            block.wantsLayer = true

            // 根据是否填充来设置颜色，参考Mac风格
            if i < filledBlocks {
                block.layer?.backgroundColor = NSColor.white.cgColor  // 填充方格：纯白色
            } else {
                block.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor  // 未填充：更透明的白色
            }

            block.layer?.cornerRadius = 0.5  // 更小的圆角，更精致
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

            // 创建容器视图，添加Mac风格的背景
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight))
            containerView.wantsLayer = true
            containerView.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.99).cgColor
            containerView.layer?.cornerRadius = 12
            containerView.layer?.masksToBounds = true

            // 添加轻微的阴影效果
            containerView.layer?.shadowColor = NSColor.black.cgColor
            containerView.layer?.shadowOpacity = 0.3
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
            kAudioObjectPropertyElementMaster,
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
                if element == kAudioObjectPropertyElementMaster {
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

    // 音量变化回调
    private func volumeChanged(address _: AudioObjectPropertyAddress) {
        guard let volume = getCurrentVolume() else {
            #if DEBUG
            print("Failed to read volume after change")
            #endif
            return
        }

        let percentage = Int(volume * 100)
        DispatchQueue.main.async {
            self.volumePercentage = percentage
            self.showVolumeHUD(percentage: percentage)
            #if DEBUG
            print("Volume changed: \(percentage)%")
            #endif
        }
    }

    // 默认设备变化回调
    private func deviceChanged() {
        stopListening()
        updateDefaultOutputDevice()
        startListening()
        if let volume = getCurrentVolume() {
            let percentage = Int(volume * 100)
            self.volumePercentage = percentage
            #if DEBUG
            print("Device switched, new volume: \(percentage)%")
            #endif
        }
        // 更新当前设备
        DispatchQueue.main.async {
            if self.defaultOutputDeviceID != 0,
               let currentDevice = self.audioDevices.first(where: { $0.id == self.defaultOutputDeviceID }) {
                self.currentDevice = currentDevice
            }
        }
    }

    // 显示音量 HUD
    private func showVolumeHUD(percentage: Int) {
        // 计算填充的方格数量（16个方格对应0-100%）
        let filledBlocks = Int(round(Float(percentage) / 100.0 * 16.0))

        // 预计算文本宽度以调整窗口大小
        let deviceName = currentDevice?.name ?? "未知设备"
        let volumeString = "\(filledBlocks)/16"
        let deviceNSString = NSString(string: deviceName)
        let deviceFont = NSFont.systemFont(ofSize: 12)
        let deviceTextSize = deviceNSString.size(withAttributes: [.font: deviceFont])
        let volumeNSString = NSString(string: volumeString)
        let volumeFont = NSFont.systemFont(ofSize: 12)
        let volumeTextSize = volumeNSString.size(withAttributes: [.font: volumeFont])
        let gapBetweenDeviceAndCount: CGFloat = 8
        let combinedWidth = deviceTextSize.width + gapBetweenDeviceAndCount + volumeTextSize.width
        let marginX: CGFloat = 16
        let dynamicHudWidth = max(320, combinedWidth + 2 * marginX)  // 最小320，确保文本不被裁剪

        for hudWindow in hudWindows {
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

            // 创建音量图标
            let speakerImage = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume")
            let speakerImageView = NSImageView(image: speakerImage!)
            speakerImageView.frame = NSRect(x: 0, y: 0, width: 44, height: 44)
            speakerImageView.imageScaling = .scaleProportionallyUpOrDown
            speakerImageView.contentTintColor = NSColor.white.withAlphaComponent(0.9)

            // 创建音量方格视图
            let blocksView = createVolumeBlocksView(filledBlocks: filledBlocks)

            // 创建设备名称标签
            let deviceLabel = NSTextField(labelWithString: deviceName)
            deviceLabel.textColor = NSColor.white.withAlphaComponent(0.8)
            deviceLabel.font = .systemFont(ofSize: 12, weight: .regular)
            deviceLabel.alignment = .left
            deviceLabel.isBordered = false
            deviceLabel.backgroundColor = .clear
            deviceLabel.isEditable = false
            deviceLabel.isSelectable = false

            // 创建音量格数标签
            let volumeText = NSTextField(labelWithString: volumeString)
            volumeText.textColor = NSColor.white.withAlphaComponent(0.8)
            volumeText.font = .systemFont(ofSize: 12, weight: .regular)
            volumeText.alignment = .left
            volumeText.isBordered = false
            volumeText.backgroundColor = .clear
            volumeText.isEditable = false
            volumeText.isSelectable = false

            // 新布局：图标、设备名+格数文本同行、音量块
            let spacingIconToDevice: CGFloat = 12
            let spacingDeviceToBlocks: CGFloat = 12
            let iconHeight = speakerImageView.frame.height
            let blocksHeight = blocksView.frame.height
            let deviceLabelHeight: CGFloat = 18
            let volumeTextHeight: CGFloat = 18

            // 计算三者总高度（含间距）
            let totalContentHeight = iconHeight + spacingIconToDevice + deviceLabelHeight + spacingDeviceToBlocks + blocksHeight
            let startY = (hudHeight - totalContentHeight) / 2

            // 图标
            speakerImageView.frame.origin = CGPoint(
                x: (dynamicHudWidth - speakerImageView.frame.width) / 2,
                y: hudHeight - startY - iconHeight
            )

            // 设备名和音量格数：作为一个整体居中显示
            let combinedStartX = (dynamicHudWidth - combinedWidth) / 2
            let textY = speakerImageView.frame.origin.y - spacingIconToDevice - deviceLabelHeight

            // 增加缓冲宽度以避免裁剪
            let buffer: CGFloat = 10
            deviceLabel.frame = NSRect(
                x: combinedStartX,
                y: textY,
                width: deviceTextSize.width + buffer,
                height: deviceLabelHeight
            )

            volumeText.frame = NSRect(
                x: combinedStartX + deviceTextSize.width + gapBetweenDeviceAndCount,
                y: textY,
                width: volumeTextSize.width + buffer,
                height: volumeTextHeight
            )

            // 方格
            blocksView.frame.origin = CGPoint(
                x: (dynamicHudWidth - blocksView.frame.width) / 2,
                y: deviceLabel.frame.origin.y - spacingDeviceToBlocks - blocksHeight
            )

            containerView.addSubview(speakerImageView)
            containerView.addSubview(blocksView)
            containerView.addSubview(deviceLabel)
            containerView.addSubview(volumeText)

            hudWindow.makeKeyAndOrderFront(nil)
        }

        // 取消之前的隐藏任务
        hideHUDWorkItem?.cancel()

        // 创建新的隐藏任务
        let workItem = DispatchWorkItem {
            for hudWindow in self.hudWindows {
                hudWindow.orderOut(nil)
            }
        }
        hideHUDWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hudDisplayDuration, execute: workItem)
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
        guard let volumeListener = volumeListener, let deviceListener = deviceListener, let audioQueue = audioQueue else { return }

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        for element in volumeElements {
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            AudioObjectRemovePropertyListenerBlock(defaultOutputDeviceID, &volumeAddress, audioQueue, volumeListener)
        }

        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, audioQueue, deviceListener)

        self.volumeListener = nil
        self.deviceListener = nil
        #if DEBUG
        print("Stopped listening")
        #endif
    }
}
