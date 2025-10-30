import AudioToolbox
import Cocoa
import Combine

// VolumeMonitor class - coordinates volume monitoring and HUD display
class VolumeMonitor: ObservableObject {
    @Published var volumePercentage: Int = 0
    @Published var audioDevices: [AudioDevice] = []
    @Published var currentDevice: AudioDevice?

    private let deviceManager = AudioDeviceManager()
    private let state = VolumeStateStore()
    private let systemEventMonitor = SystemEventMonitor()
    private let hudEventSubject = PassthroughSubject<VolumeHUDContext, Never>()

    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var audioQueue: DispatchQueue?

    init() {
        audioQueue = DispatchQueue(label: "com.volumegrid.audio", qos: .userInitiated)

        let deviceID = updateDefaultOutputDevice()
        if deviceID != 0 {
            if let volume = getCurrentVolume() {
                volumePercentage = Int(volume * 100)
                state.updateLastVolumeScalar(CGFloat(volume))
            }
            _ = refreshMuteState()
        }

        getAudioDevices()
    }

    deinit {
        stopListening()
    }

    var hudEvents: AnyPublisher<VolumeHUDContext, Never> {
        hudEventSubject.eraseToAnyPublisher()
    }

    // MARK: - Device Management

    @discardableResult
    private func updateDefaultOutputDevice() -> AudioDeviceID {
        let deviceID = deviceManager.getDefaultOutputDevice()
        state.updateDefaultOutputDeviceID(deviceID)
        return deviceID
    }

    func getAudioDevices() {
        let devices = deviceManager.getAllDevices()

        DispatchQueue.main.async {
            self.audioDevices = devices
            let existingID = self.state.defaultOutputDeviceIDValue()
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

        state.updateVolumeElements(elements)
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

            let elements = self.state.volumeElementsSnapshot()
            guard !elements.isEmpty else { return }

            _ = self.deviceManager.setVolume(clampedScalar, for: deviceID, elements: elements)

            if clampedScalar > 0 {
                let muteElements = self.state.muteElementsSnapshot()
                if !muteElements.isEmpty {
                    _ = self.deviceManager.setMuteState(
                        false, for: deviceID, elements: muteElements)
                }
            }

            let uiScalar = CGFloat(clampedScalar)
            DispatchQueue.main.async {
                self.state.updateLastVolumeScalar(uiScalar)
                self.volumePercentage = Int(round(uiScalar * 100))
                if clampedScalar > 0 {
                    self.state.setDeviceMuted(false)
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
            let currentID = state.defaultOutputDeviceIDValue()
            let effectiveID = currentID != 0 ? currentID : updateDefaultOutputDevice()
            guard effectiveID != 0 else {
                state.setDeviceMuted(false)
                return nil
            }
            resolvedDeviceID = effectiveID
        }

        let elements = deviceManager.detectMuteElements(for: resolvedDeviceID)
        guard !elements.isEmpty else {
            state.setDeviceMuted(false)
            return nil
        }

        state.updateMuteElements(elements)

        if let muted = deviceManager.getMuteState(for: resolvedDeviceID, elements: elements) {
            state.setDeviceMuted(muted)
            if muted {
                volumePercentage = 0
            }
            return muted
        }

        state.setDeviceMuted(false)
        return nil
    }

    // MARK: - Event Handlers

    private func volumeChanged(address _: AudioObjectPropertyAddress) {
        guard let volume = getCurrentVolume() else { return }

        let clampedVolume = max(0, min(volume, 1))
        let percentage = Int(round(clampedVolume * 100))

        DispatchQueue.main.async {
            let previousScalar = self.state.lastVolumeScalarSnapshot()
            let currentScalar = CGFloat(clampedVolume)
            self.state.updateLastVolumeScalar(currentScalar)
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

            if currentScalar > epsilon, self.state.deviceMuted() {
                self.state.setDeviceMuted(false)
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

        let currentOutputID = state.defaultOutputDeviceIDValue()
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
            self.state.updateLastVolumeScalar(CGFloat(clamped))
            self.showVolumeHUD(volumeScalar: CGFloat(clamped))
        } else {
            self.volumePercentage = 0
            self.state.updateLastVolumeScalar(0)
            self.showVolumeHUD(volumeScalar: 0, isUnsupported: true)
        }
    }

    // MARK: - HUD Display

    private func showVolumeHUD(volumeScalar: CGFloat, isUnsupported: Bool = false) {
        emitHUDEvent(volumeScalar: volumeScalar, isUnsupported: isUnsupported)
    }

    private func showHUDForCurrentVolume() {
        _ = refreshMuteState()
        if let volume = getCurrentVolume() {
            let clamped = max(0, min(volume, 1))
            let scalar = CGFloat(clamped)
            state.updateLastVolumeScalar(scalar)
            if state.deviceMuted() {
                volumePercentage = 0
            } else {
                volumePercentage = Int(round(clamped * 100))
            }
            showVolumeHUD(volumeScalar: scalar, isUnsupported: false)
        } else if let lastScalar = state.lastVolumeScalarSnapshot() {
            showVolumeHUD(volumeScalar: lastScalar, isUnsupported: true)
        } else {
            showVolumeHUD(volumeScalar: 0, isUnsupported: true)
        }
    }

    // MARK: - Listener Management

    func startListening() {
        let deviceID = updateDefaultOutputDevice()
        guard deviceID != 0 else { return }

        if state.isListeningActive() {
            if state.listeningDeviceIDValue() == deviceID {
                return
            }
            stopListening()
        }

        state.updateRegisteredVolumeElements([])
        state.updateRegisteredMuteElements([])

        let volumeElements = deviceManager.detectVolumeElements(for: deviceID)
        let supportsVolume = !volumeElements.isEmpty

        if !supportsVolume {
            state.updateMuteElements([])
        }

        if supportsVolume {
            state.updateVolumeElements(volumeElements)
            let muteElements = deviceManager.detectMuteElements(for: deviceID)
            state.updateMuteElements(muteElements)
            _ = refreshMuteState(for: deviceID)

            volumeListener = {
                [weak self] (_: UInt32, inAddresses: UnsafePointer<AudioObjectPropertyAddress>) in
                guard let self = self else { return }
                self.volumeChanged(address: inAddresses.pointee)
            }

            guard let audioQueue = audioQueue, let volumeListener = volumeListener else { return }

            var listenerRegistered = false
            let volumeElementsSnapshot = state.volumeElementsSnapshot()
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
            state.updateRegisteredVolumeElements(volumeElementsSnapshot)

            let muteElementsSnapshot = state.muteElementsSnapshot()
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
                    state.updateRegisteredMuteElements(validMuteElements)
                }
            }
        }

        systemEventMonitor.start { [weak self] in
            self?.showHUDForCurrentVolume()
        }

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

        state.updateListeningDeviceID(deviceID)
        state.setListeningActive(true)
    }

    func stopListening() {
        systemEventMonitor.stop()

        guard let audioQueue = audioQueue else {
            volumeListener = nil
            deviceListener = nil
            muteListener = nil
            state.updateListeningDeviceID(nil)
            state.updateRegisteredVolumeElements([])
            state.updateRegisteredMuteElements([])
            state.setListeningActive(false)
            return
        }

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        let removalDeviceID =
            state.listeningDeviceIDValue() ?? state.defaultOutputDeviceIDValue()

        if let volumeListener = volumeListener {
            let registeredVolumes = state.registeredVolumeElementsSnapshot()
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
            let registeredMutes = state.registeredMuteElementsSnapshot()
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

        volumeListener = nil
        deviceListener = nil
        muteListener = nil
        state.updateListeningDeviceID(nil)
        state.updateRegisteredVolumeElements([])
        state.updateRegisteredMuteElements([])
        state.setListeningActive(false)
    }

    // MARK: - HUD Event Broadcasting

    private func emitHUDEvent(volumeScalar: CGFloat, isUnsupported: Bool) {
        let context = VolumeHUDContext(
            volumeScalar: volumeScalar,
            deviceName: currentDevice?.name,
            isMuted: state.deviceMuted(),
            isUnsupported: isUnsupported
        )

        if Thread.isMainThread {
            hudEventSubject.send(context)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hudEventSubject.send(context)
            }
        }
    }
}
