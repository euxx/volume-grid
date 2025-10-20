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
    private var hudWindow: NSWindow?
    private var audioQueue: DispatchQueue?
    private var hideHUDWorkItem: DispatchWorkItem?

    // HUD 常量
    private let hudWidth: CGFloat = 300
    private let hudHeight: CGFloat = 100
    private let hudAlpha: CGFloat = 0.7
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

    // 设置 HUD 窗口
    private func setupHUDWindow() {
        hudWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hudWindow?.level = .floating
        hudWindow?.backgroundColor = .black.withAlphaComponent(hudAlpha)
        hudWindow?.isOpaque = false
        hudWindow?.center()

        // 创建容器视图，添加边距
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight))

        let text = NSTextField(labelWithString: "音量: --")
        text.textColor = .white
        text.font = .systemFont(ofSize: hudFontSize)
        text.alignment = .center
        text.maximumNumberOfLines = 2  // 支持多行
        text.cell?.truncatesLastVisibleLine = false  // 不截断最后一行
        text.isBordered = false
        text.backgroundColor = .clear

        // 设置文本字段的边距
        let margin: CGFloat = 20
        text.frame = NSRect(x: margin, y: margin, width: hudWidth - 2 * margin, height: hudHeight - 2 * margin)

        containerView.addSubview(text)
        hudWindow?.contentView = containerView
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

    // 检查设备是否支持音量控制
    private func deviceSupportsVolumeControl(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )
        return AudioObjectHasProperty(deviceID, &address)
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

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )

        var volume: Float32 = 0.0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)

        if status == noErr {
            DispatchQueue.main.async {
                self.volumePercentage = Int(volume * 100)
            }
            return volume
        } else {
            #if DEBUG
            print("Error getting volume: \(status)")
            #endif
            return nil
        }
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
    private func volumeChanged(address: AudioObjectPropertyAddress) {
        let deviceID = self.defaultOutputDeviceID
        var address = address
        var volume: Float32 = 0.0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)

        if status == noErr {
            let percentage = Int(volume * 100)
            DispatchQueue.main.async {
                self.volumePercentage = percentage
                self.showVolumeHUD(percentage: percentage)
                #if DEBUG
                print("Volume changed: \(percentage)%")
                #endif
            }
        } else {
            #if DEBUG
            print("Error in volume changed: \(status)")
            #endif
        }
    }

    // 默认设备变化回调
    private func deviceChanged() {
        stopListening()
        updateDefaultOutputDevice()
        startListening()
        if let volume = getCurrentVolume() {
            #if DEBUG
            print("Device switched, new volume: \(Int(volume * 100))%")
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
        guard let hudWindow = hudWindow, let containerView = hudWindow.contentView, let textField = containerView.subviews.first as? NSTextField else { return }

        let deviceName = currentDevice?.name ?? "未知设备"
        textField.stringValue = "音量: \(percentage)%\n\(deviceName)"

        // 取消之前的隐藏任务
        hideHUDWorkItem?.cancel()

        hudWindow.makeKeyAndOrderFront(nil)

        // 创建新的隐藏任务
        let workItem = DispatchWorkItem {
            hudWindow.orderOut(nil)
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
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )

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

        let volumeStatus = AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, audioQueue, volumeListener)
        if volumeStatus != noErr {
            #if DEBUG
            print("Error adding volume listener: \(volumeStatus)")
            #endif
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

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        AudioObjectRemovePropertyListenerBlock(defaultOutputDeviceID, &volumeAddress, audioQueue, volumeListener)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, audioQueue, deviceListener)

        self.volumeListener = nil
        self.deviceListener = nil
        #if DEBUG
        print("Stopped listening")
        #endif
    }
}
