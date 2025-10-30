import AudioToolbox
import Cocoa
import Combine
import SwiftUI

// VolumeMonitor class - coordinates volume monitoring and HUD display
class VolumeMonitor: ObservableObject {
    @Published var volumePercentage: Int = 0
    @Published var audioDevices: [AudioDevice] = []
    @Published var currentDevice: AudioDevice?

    private let deviceManager = AudioDeviceManager()
    private let hudManager = HUDManager()
    private let stateLock = NSLock()

    private var defaultOutputDeviceID: AudioDeviceID = 0
    private var listeningDeviceID: AudioDeviceID?
    private var volumeElements: [AudioObjectPropertyElement] = []
    private var muteElements: [AudioObjectPropertyElement] = []
    private var registeredVolumeElements: [AudioObjectPropertyElement] = []
    private var registeredMuteElements: [AudioObjectPropertyElement] = []
    private var lastVolumeScalar: CGFloat?
    private var isDeviceMuted: Bool = false
    private var isListening = false

    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var audioQueue: DispatchQueue?

    private var globalSystemEventMonitor: Any?
    private var localSystemEventMonitor: Any?
    private var lastHandledSystemEvent: (timestamp: TimeInterval, data: Int)?

    init() {
        audioQueue = DispatchQueue(label: "com.volumegrid.audio", qos: .userInitiated)

        let deviceID = updateDefaultOutputDevice()
        if deviceID != 0 {
            if let volume = getCurrentVolume() {
                volumePercentage = Int(volume * 100)
                lastVolumeScalar = CGFloat(volume)
            }
            _ = refreshMuteState()
        }

        getAudioDevices()
    }

    deinit {
        stopListening()
    }

    // MARK: - Thread-safe property accessors

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func setDefaultOutputDeviceID(_ id: AudioDeviceID) {
        withStateLock { defaultOutputDeviceID = id }
    }

    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        withStateLock { defaultOutputDeviceID }
    }

    private func setListeningDeviceID(_ id: AudioDeviceID?) {
        withStateLock { listeningDeviceID = id }
    }

    private func getListeningDeviceID() -> AudioDeviceID? {
        withStateLock { listeningDeviceID }
    }

    private func setVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withStateLock { volumeElements = elements }
    }

    private func getVolumeElements() -> [AudioObjectPropertyElement] {
        withStateLock { volumeElements }
    }

    private func setMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withStateLock { muteElements = elements }
    }

    private func getMuteElements() -> [AudioObjectPropertyElement] {
        withStateLock { muteElements }
    }

    private func setRegisteredVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withStateLock { registeredVolumeElements = elements }
    }

    private func getRegisteredVolumeElements() -> [AudioObjectPropertyElement] {
        withStateLock { registeredVolumeElements }
    }

    private func setRegisteredMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withStateLock { registeredMuteElements = elements }
    }

    private func getRegisteredMuteElements() -> [AudioObjectPropertyElement] {
        withStateLock { registeredMuteElements }
    }

    // MARK: - Device Management

    @discardableResult
    private func updateDefaultOutputDevice() -> AudioDeviceID {
        let deviceID = deviceManager.getDefaultOutputDevice()
        setDefaultOutputDeviceID(deviceID)
        return deviceID
    }

    func getAudioDevices() {
        let devices = deviceManager.getAllDevices()

        DispatchQueue.main.async {
            self.audioDevices = devices
            let existingID = self.getDefaultOutputDeviceID()
            let resolvedID = existingID != 0 ? existingID : self.updateDefaultOutputDevice()
            if resolvedID != 0, let currentDevice = devices.first(where: { $0.id == resolvedID }) {
                self.currentDevice = currentDevice
            }
        }
    }

    // MARK: - Volume Control

    func getCurrentVolume() -> Float32? {
        let deviceID = updateDefaultOutputDevice()
        guard deviceID != 0 else { return nil }

        let elements = deviceManager.detectVolumeElements(for: deviceID)
        guard !elements.isEmpty else { return nil }

        setVolumeElements(elements)
        return deviceManager.getCurrentVolume(for: deviceID, elements: elements)
    }

    func setVolume(percentage: Int) {
        let clamped = max(0, min(percentage, 100))
        let scalar = Float32(Double(clamped) / 100.0)
        setVolume(scalar: scalar)
    }

    func setVolume(scalar: Float32) {
        let clampedScalar = max(0, min(scalar, 1))

        guard let audioQueue else { return }

        audioQueue.async { [weak self] in
            guard let self else { return }

            let deviceID = self.updateDefaultOutputDevice()
            guard deviceID != 0 else { return }

            let elements = self.getVolumeElements()
            guard !elements.isEmpty else { return }

            _ = self.deviceManager.setVolume(clampedScalar, for: deviceID, elements: elements)

            if clampedScalar > 0 {
                let muteElements = self.getMuteElements()
                if !muteElements.isEmpty {
                    _ = self.deviceManager.setMuteState(
                        false, for: deviceID, elements: muteElements)
                }
            }

            let uiScalar = CGFloat(clampedScalar)
            DispatchQueue.main.async {
                self.lastVolumeScalar = uiScalar
                self.volumePercentage = Int(round(uiScalar * 100))
                if clampedScalar > 0 {
                    self.isDeviceMuted = false
                }
            }
        }
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
            let currentID = getDefaultOutputDeviceID()
            let effectiveID = currentID != 0 ? currentID : updateDefaultOutputDevice()
            guard effectiveID != 0 else {
                isDeviceMuted = false
                return nil
            }
            resolvedDeviceID = effectiveID
        }

        let elements = deviceManager.detectMuteElements(for: resolvedDeviceID)
        guard !elements.isEmpty else {
            isDeviceMuted = false
            return nil
        }

        setMuteElements(elements)

        if let muted = deviceManager.getMuteState(for: resolvedDeviceID, elements: elements) {
            isDeviceMuted = muted
            if muted {
                volumePercentage = 0
            }
            return muted
        }

        isDeviceMuted = false
        return nil
    }

    // MARK: - Event Handlers

    private func volumeChanged(address _: AudioObjectPropertyAddress) {
        guard let volume = getCurrentVolume() else { return }

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
                shouldShowHUD = abs(previousScalar - currentScalar) > epsilon
                if !shouldShowHUD {
                    let isAtLowerBound = previousScalar <= epsilon && currentScalar <= epsilon
                    let isAtUpperBound =
                        previousScalar >= (1 - epsilon) && currentScalar >= (1 - epsilon)
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
        }
    }

    private func muteChanged(address _: AudioObjectPropertyAddress) {
        DispatchQueue.main.async {
            self.showHUDForCurrentVolume()
        }
    }

    private func deviceChanged() {
        stopListening()
        updateDefaultOutputDevice()
        getAudioDevices()
        startListening()

        let currentOutputID = getDefaultOutputDeviceID()
        if currentOutputID != 0 {
            if let current = audioDevices.first(where: { $0.id == currentOutputID }) {
                currentDevice = current
            } else if let name = deviceManager.getDeviceName(currentOutputID) {
                currentDevice = AudioDevice(id: currentOutputID, name: name)
            } else {
                currentDevice = nil
            }
        } else {
            currentDevice = nil
        }

        if currentOutputID != 0 && deviceManager.supportsVolumeControl(currentOutputID) {
            _ = refreshMuteState()
        }

        if let volume = getCurrentVolume() {
            let clamped = max(0, min(volume, 1))
            let percentage = Int(round(clamped * 100))
            self.volumePercentage = percentage
            self.lastVolumeScalar = CGFloat(clamped)
            self.showVolumeHUD(volumeScalar: CGFloat(clamped))
        } else {
            self.volumePercentage = 0
            self.lastVolumeScalar = 0
            self.showVolumeHUD(volumeScalar: 0, isUnsupported: true)
        }
    }

    // MARK: - HUD Display

    private func showVolumeHUD(volumeScalar: CGFloat, isUnsupported: Bool = false) {
        hudManager.showHUD(
            volumeScalar: volumeScalar,
            deviceName: currentDevice?.name,
            isMuted: isDeviceMuted,
            isUnsupported: isUnsupported
        )
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
            showVolumeHUD(volumeScalar: scalar, isUnsupported: false)
        } else if let lastScalar = lastVolumeScalar {
            showVolumeHUD(volumeScalar: lastScalar, isUnsupported: true)
        } else {
            showVolumeHUD(volumeScalar: 0, isUnsupported: true)
        }
    }

    // MARK: - Key Monitoring

    private func startKeyMonitoring() {
        if globalSystemEventMonitor == nil {
            globalSystemEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
                [weak self] event in
                DispatchQueue.main.async {
                    self?.handleSystemDefinedEvent(event)
                }
            }
        }

        if localSystemEventMonitor == nil {
            localSystemEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) {
                [weak self] event in
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
        let keyCode = (event.data1 & 0xFFFF_0000) >> 16
        let keyFlags = event.data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0xA
        guard isKeyDown else { return }

        let signature = (timestamp: event.timestamp, data: event.data1)
        if let last = lastHandledSystemEvent,
            abs(last.timestamp - signature.timestamp) < 0.0001,
            last.data == signature.data
        {
            return
        }
        lastHandledSystemEvent = signature

        switch keyCode & 0xFF {
        case 0, 1, 7:
            showHUDForCurrentVolume()
        default:
            break
        }
    }

    // MARK: - Listener Management

    func startListening() {
        let deviceID = updateDefaultOutputDevice()
        guard deviceID != 0 else { return }

        if isListening {
            if getListeningDeviceID() == deviceID {
                return
            }
            stopListening()
        }

        setRegisteredVolumeElements([])
        setRegisteredMuteElements([])

        let volumeElements = deviceManager.detectVolumeElements(for: deviceID)
        let supportsVolume = !volumeElements.isEmpty

        if !supportsVolume {
            setMuteElements([])
        }

        if supportsVolume {
            setVolumeElements(volumeElements)
            let muteElements = deviceManager.detectMuteElements(for: deviceID)
            setMuteElements(muteElements)
            _ = refreshMuteState(for: deviceID)

            volumeListener = {
                [weak self] (_: UInt32, inAddresses: UnsafePointer<AudioObjectPropertyAddress>) in
                guard let self = self else { return }
                self.volumeChanged(address: inAddresses.pointee)
            }

            guard let audioQueue = audioQueue, let volumeListener = volumeListener else { return }

            var listenerRegistered = false
            let volumeElementsSnapshot = getVolumeElements()
            for element in volumeElementsSnapshot {
                var volumeAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )

                let volumeStatus = AudioObjectAddPropertyListenerBlock(
                    deviceID, &volumeAddress, audioQueue, volumeListener)
                if volumeStatus == noErr {
                    listenerRegistered = true
                }
            }

            guard listenerRegistered else { return }
            setRegisteredVolumeElements(volumeElementsSnapshot)

            let muteElementsSnapshot = getMuteElements()
            if !muteElementsSnapshot.isEmpty {
                muteListener = {
                    [weak self] (_: UInt32, inAddresses: UnsafePointer<AudioObjectPropertyAddress>)
                    in
                    guard let self = self else { return }
                    self.muteChanged(address: inAddresses.pointee)
                }

                if let muteListener = muteListener {
                    var validMuteElements: [AudioObjectPropertyElement] = []
                    for element in muteElementsSnapshot {
                        var muteAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyMute,
                            mScope: kAudioDevicePropertyScopeOutput,
                            mElement: element
                        )

                        if AudioObjectHasProperty(deviceID, &muteAddress) {
                            var muted: UInt32 = 0
                            var size = UInt32(MemoryLayout<UInt32>.size)
                            let readStatus = AudioObjectGetPropertyData(
                                deviceID, &muteAddress, 0, nil, &size, &muted)

                            if readStatus == noErr {
                                let muteStatus = AudioObjectAddPropertyListenerBlock(
                                    deviceID, &muteAddress, audioQueue, muteListener)
                                if muteStatus == noErr {
                                    validMuteElements.append(element)
                                }
                            }
                        }
                    }
                    setRegisteredMuteElements(validMuteElements)
                }
            }
        }

        startKeyMonitoring()

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        deviceListener = { [weak self] (_: UInt32, _: UnsafePointer<AudioObjectPropertyAddress>) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.deviceChanged()
            }
        }

        guard let audioQueue = audioQueue, let deviceListener = deviceListener else { return }

        let deviceStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, audioQueue, deviceListener)
        if deviceStatus != noErr {
            return
        }

        setListeningDeviceID(deviceID)
        isListening = true
    }

    func stopListening() {
        stopKeyMonitoring()
        guard let audioQueue = audioQueue else {
            volumeListener = nil
            deviceListener = nil
            muteListener = nil
            setListeningDeviceID(nil)
            setRegisteredVolumeElements([])
            setRegisteredMuteElements([])
            isListening = false
            return
        }

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        let removalDeviceID = getListeningDeviceID() ?? getDefaultOutputDeviceID()

        if let volumeListener = volumeListener {
            let registeredVolumes = getRegisteredVolumeElements()
            for element in registeredVolumes {
                var volumeAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                if removalDeviceID != 0 {
                    AudioObjectRemovePropertyListenerBlock(
                        removalDeviceID, &volumeAddress, audioQueue, volumeListener)
                }
            }
        }

        if let muteListener = muteListener {
            let registeredMutes = getRegisteredMuteElements()
            for element in registeredMutes {
                var muteAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyMute,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                if removalDeviceID != 0 {
                    AudioObjectRemovePropertyListenerBlock(
                        removalDeviceID, &muteAddress, audioQueue, muteListener)
                }
            }
        }

        if let deviceListener = deviceListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &deviceAddress, audioQueue, deviceListener)
        }

        self.volumeListener = nil
        self.deviceListener = nil
        self.muteListener = nil
        setListeningDeviceID(nil)
        setRegisteredVolumeElements([])
        setRegisteredMuteElements([])
        isListening = false
    }
}
