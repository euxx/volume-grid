import SwiftUI
import Combine
import Cocoa
import AudioToolbox

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
        }
        .padding()
        .onAppear {
            volumeMonitor.startListening()
        }
        .onDisappear {
            volumeMonitor.stopListening()
        }
    }
}

// VolumeMonitor 类
class VolumeMonitor: ObservableObject {
    @Published var volumePercentage: Int = 0
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

        let text = NSTextField(labelWithString: "音量: --")
        text.textColor = .white
        text.font = .systemFont(ofSize: hudFontSize)
        text.alignment = .center
        hudWindow?.contentView = text
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
    }

    // 显示音量 HUD
    private func showVolumeHUD(percentage: Int) {
        guard let hudWindow = hudWindow, let textField = hudWindow.contentView as? NSTextField else { return }
        textField.stringValue = "音量: \(percentage)%"

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
