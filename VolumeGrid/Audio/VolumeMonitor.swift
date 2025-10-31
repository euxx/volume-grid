import AudioToolbox
import Cocoa
@preconcurrency import Combine
@preconcurrency import os.lock

struct HUDEvent {
    let volumeScalar: CGFloat
    let deviceName: String?
    let isMuted: Bool
    let isUnsupported: Bool
}

private final class VolumeStateStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()

    private nonisolated(unsafe) var defaultOutputDeviceID: AudioDeviceID = 0
    private nonisolated(unsafe) var listeningDeviceID: AudioDeviceID?
    private nonisolated(unsafe) var volumeElements: [AudioObjectPropertyElement] = []
    private nonisolated(unsafe) var muteElements: [AudioObjectPropertyElement] = []
    private nonisolated(unsafe) var registeredVolumeElements: [AudioObjectPropertyElement] = []
    private nonisolated(unsafe) var registeredMuteElements: [AudioObjectPropertyElement] = []
    private nonisolated(unsafe) var lastVolumeScalar: CGFloat?
    private nonisolated(unsafe) var isDeviceMuted = false
    private nonisolated(unsafe) var isListening = false

    nonisolated init() {}

    // MARK: - Device IDs

    nonisolated func updateDefaultOutputDeviceID(_ id: AudioDeviceID) {
        lock.lock()
        defaultOutputDeviceID = id
        lock.unlock()
    }

    nonisolated func defaultOutputDeviceIDValue() -> AudioDeviceID {
        lock.lock()
        defer { lock.unlock() }
        return defaultOutputDeviceID
    }

    nonisolated func updateListeningDeviceID(_ id: AudioDeviceID?) {
        lock.lock()
        listeningDeviceID = id
        lock.unlock()
    }

    nonisolated func listeningDeviceIDValue() -> AudioDeviceID? {
        lock.lock()
        defer { lock.unlock() }
        return listeningDeviceID
    }

    // MARK: - Volume Elements

    nonisolated func updateVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        lock.lock()
        volumeElements = elements
        lock.unlock()
    }

    nonisolated func volumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        lock.lock()
        defer { lock.unlock() }
        return volumeElements
    }

    nonisolated func updateMuteElements(_ elements: [AudioObjectPropertyElement]) {
        lock.lock()
        muteElements = elements
        lock.unlock()
    }

    nonisolated func muteElementsSnapshot() -> [AudioObjectPropertyElement] {
        lock.lock()
        defer { lock.unlock() }
        return muteElements
    }

    nonisolated func updateRegisteredVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        lock.lock()
        registeredVolumeElements = elements
        lock.unlock()
    }

    nonisolated func registeredVolumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        lock.lock()
        defer { lock.unlock() }
        return registeredVolumeElements
    }

    nonisolated func updateRegisteredMuteElements(_ elements: [AudioObjectPropertyElement]) {
        lock.lock()
        registeredMuteElements = elements
        lock.unlock()
    }

    nonisolated func registeredMuteElementsSnapshot() -> [AudioObjectPropertyElement] {
        lock.lock()
        defer { lock.unlock() }
        return registeredMuteElements
    }

    // MARK: - Volume Muted State

    nonisolated func setDeviceMuted(_ muted: Bool) {
        lock.lock()
        isDeviceMuted = muted
        lock.unlock()
    }

    nonisolated func deviceMuted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isDeviceMuted
    }

    // MARK: - Volume Scalar

    nonisolated func updateLastVolumeScalar(_ scalar: CGFloat?) {
        lock.lock()
        lastVolumeScalar = scalar
        lock.unlock()
    }

    nonisolated func lastVolumeScalarSnapshot() -> CGFloat? {
        lock.lock()
        defer { lock.unlock() }
        return lastVolumeScalar
    }

    // MARK: - Listening flag

    nonisolated func setListeningActive(_ active: Bool) {
        lock.lock()
        isListening = active
        lock.unlock()
    }

    nonisolated func isListeningActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isListening
    }
}

@MainActor
class VolumeMonitor: ObservableObject {
    @Published var volumePercentage: Int = 0
    @Published var audioDevices: [AudioDevice] = []
    @Published var currentDevice: AudioDevice?
    @Published var isCurrentDeviceVolumeSupported: Bool = false

    // MARK: - Helper Methods

    private nonisolated func resolveDeviceID() -> AudioDeviceID {
        let currentID = state.defaultOutputDeviceIDValue()
        return currentID != 0 ? currentID : updateDefaultOutputDevice()
    }

    private nonisolated let deviceManager = AudioDeviceManager()
    private nonisolated let state = VolumeStateStore()
    private let systemEventMonitor = SystemEventMonitor()
    private nonisolated let hudEventSubject: PassthroughSubject<HUDEvent, Never> = {
        PassthroughSubject<HUDEvent, Never>()
    }()
    private var volumeChangeDebouncer: DispatchWorkItem?

    private let listenerLock = NSLock()
    private nonisolated(unsafe) var _volumeListener: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var _deviceListener: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var _muteListener: AudioObjectPropertyListenerBlock?

    nonisolated private var volumeListener: AudioObjectPropertyListenerBlock? {
        get {
            listenerLock.lock()
            defer { listenerLock.unlock() }
            return _volumeListener
        }
        set {
            listenerLock.lock()
            defer { listenerLock.unlock() }
            _volumeListener = newValue
        }
    }

    nonisolated private var deviceListener: AudioObjectPropertyListenerBlock? {
        get {
            listenerLock.lock()
            defer { listenerLock.unlock() }
            return _deviceListener
        }
        set {
            listenerLock.lock()
            defer { listenerLock.unlock() }
            _deviceListener = newValue
        }
    }

    nonisolated private var muteListener: AudioObjectPropertyListenerBlock? {
        get {
            listenerLock.lock()
            defer { listenerLock.unlock() }
            return _muteListener
        }
        set {
            listenerLock.lock()
            defer { listenerLock.unlock() }
            _muteListener = newValue
        }
    }

    private nonisolated let audioQueue: DispatchQueue = DispatchQueue(
        label: "com.volumegrid.audio", qos: .userInitiated
    )

    init() {
        let deviceID = updateDefaultOutputDevice()
        isCurrentDeviceVolumeSupported =
            deviceID != 0 && deviceManager.supportsVolumeControl(deviceID)
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
        volumeChangeDebouncer?.cancel()
        if Thread.isMainThread {
            nonisolatedStopListening()
        } else {
            assertionFailure("VolumeMonitor should be deallocated on main thread")
        }
    }

    nonisolated var hudEvents: AnyPublisher<HUDEvent, Never> {
        hudEventSubject.eraseToAnyPublisher()
    }

    // MARK: - Device Management

    @discardableResult
    nonisolated private func updateDefaultOutputDevice() -> AudioDeviceID {
        let deviceID = deviceManager.getDefaultOutputDevice()
        state.updateDefaultOutputDeviceID(deviceID)
        return deviceID
    }

    func getAudioDevices() {
        let devices = deviceManager.getAllDevices()

        DispatchQueue.main.async {
            self.audioDevices = devices
            let resolvedID = self.resolveDeviceID()
            if resolvedID != 0, let currentDevice = devices.first(where: { $0.id == resolvedID }) {
                self.currentDevice = currentDevice
            }
        }
    }

    // MARK: - Volume Control

    nonisolated func getCurrentVolume() -> Float32? {
        let deviceID = resolveDeviceID()
        guard deviceID != 0 else { return nil }

        let elements = deviceManager.detectVolumeElements(for: deviceID)
        guard !elements.isEmpty else { return nil }

        state.updateVolumeElements(elements)
        return deviceManager.getCurrentVolume(for: deviceID, elements: elements)
    }

    func setVolume(percentage: Int) {
        let clamped = percentage.clamped(to: 0...100)
        let scalar = Float32(Double(clamped) / 100.0)
        setVolume(scalar: scalar)
    }

    func setVolume(scalar: Float32) {
        let clampedScalar = scalar.clamped(to: 0...1)

        audioQueue.async { [weak self] in
            guard let self else { return }

            let deviceID = self.resolveDeviceID()
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
        let resolvedDeviceID = deviceID ?? resolveDeviceID()

        guard resolvedDeviceID != 0 else {
            state.setDeviceMuted(false)
            return nil
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

        let clampedVolume = volume.clamped(to: 0...1)
        let percentage = Int(round(clampedVolume * 100))
        let currentScalar = CGFloat(clampedVolume)
        let previousScalar = state.lastVolumeScalarSnapshot()
        let epsilon: CGFloat = 0.001

        let shouldShowHUD: Bool
        if let previousScalar {
            let delta = abs(previousScalar - currentScalar)
            let isAtBoundary =
                (currentScalar <= epsilon && previousScalar <= epsilon)
                || (currentScalar >= (1 - epsilon) && previousScalar >= (1 - epsilon))
            shouldShowHUD = delta > epsilon || isAtBoundary
        } else {
            shouldShowHUD = true
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.updateLastVolumeScalar(currentScalar)
            self.volumePercentage = percentage

            if currentScalar > epsilon, self.state.deviceMuted() {
                self.state.setDeviceMuted(false)
            }

            if shouldShowHUD {
                self.volumeChangeDebouncer?.cancel()
                let debouncer = DispatchWorkItem { [weak self] in
                    self?.showVolumeHUD(volumeScalar: currentScalar)
                }
                self.volumeChangeDebouncer = debouncer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: debouncer)
            }
        }
    }

    private func muteChanged(address _: AudioObjectPropertyAddress) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            _ = self.refreshMuteState()
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
        updateVolumeSupportState(
            currentOutputID != 0 && deviceManager.supportsVolumeControl(currentOutputID))

        if currentOutputID != 0 && deviceManager.supportsVolumeControl(currentOutputID) {
            _ = refreshMuteState()
        }

        if let volume = getCurrentVolume() {
            let clamped = volume.clamped(to: 0...1)
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
        let scalar: CGFloat
        let isUnsupported: Bool

        if let volume = getCurrentVolume() {
            let clamped = volume.clamped(to: 0...1)
            scalar = CGFloat(clamped)
            state.updateLastVolumeScalar(scalar)
            volumePercentage = state.deviceMuted() ? 0 : Int(round(clamped * 100))
            isUnsupported = false
        } else {
            scalar = state.lastVolumeScalarSnapshot() ?? 0
            isUnsupported = true
        }

        showVolumeHUD(volumeScalar: scalar, isUnsupported: isUnsupported)
    }

    // MARK: - Listener Management

    func startListening() {
        let deviceID = resolveDeviceID()
        guard deviceID != 0 else {
            updateVolumeSupportState(false)
            return
        }

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
        updateVolumeSupportState(supportsVolume)

        if !supportsVolume {
            state.updateVolumeElements([])
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

            guard let volumeListener = volumeListener else { return }

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
            guard let self else { return }
            if self.isCurrentDeviceVolumeSupported {
                self.showHUDForCurrentVolume()
            } else {
                let fallbackScalar = self.state.lastVolumeScalarSnapshot() ?? 0
                self.showVolumeHUD(volumeScalar: fallbackScalar, isUnsupported: true)
            }
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

        guard let deviceListener = deviceListener else { return }

        let deviceStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, audioQueue, deviceListener)
        if deviceStatus != noErr {
            return
        }

        state.updateListeningDeviceID(deviceID)
        state.setListeningActive(true)
    }

    private nonisolated func nonisolatedStopListening() {
        // Must be called from main thread
        // SystemEventMonitor.stop() requires main thread
        assert(Thread.isMainThread, "nonisolatedStopListening must be called from main thread")

        MainActor.assumeIsolated {
            systemEventMonitor.stop()
        }

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        let removalDeviceID = state.listeningDeviceIDValue() ?? resolveDeviceID()

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

    func stopListening() {
        nonisolatedStopListening()
    }

    // MARK: - HUD Event Broadcasting

    private func emitHUDEvent(volumeScalar: CGFloat, isUnsupported: Bool) {
        let event = HUDEvent(
            volumeScalar: volumeScalar,
            deviceName: currentDevice?.name,
            isMuted: state.deviceMuted(),
            isUnsupported: isUnsupported
        )

        if Thread.isMainThread {
            hudEventSubject.send(event)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hudEventSubject.send(event)
            }
        }
    }

    private func updateVolumeSupportState(_ isSupported: Bool) {
        if Thread.isMainThread {
            isCurrentDeviceVolumeSupported = isSupported
            if !isSupported {
                state.updateLastVolumeScalar(0)
                if volumePercentage != 0 {
                    volumePercentage = 0
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCurrentDeviceVolumeSupported = isSupported
                if !isSupported {
                    self.state.updateLastVolumeScalar(0)
                    if self.volumePercentage != 0 {
                        self.volumePercentage = 0
                    }
                }
            }
        }
    }
}
