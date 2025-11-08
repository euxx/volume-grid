import AudioToolbox
import Cocoa
@preconcurrency import Combine
@preconcurrency import os.lock

struct HUDEvent {
    let volumeScalar: CGFloat
    let deviceName: String?
    let isUnsupported: Bool
}

private final class ThreadSafeProperty<T>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private nonisolated(unsafe) var value: T

    nonisolated init(_ initialValue: T) {
        self.value = initialValue
    }

    nonisolated func get() -> T {
        lock.withLock {
            value
        }
    }

    nonisolated func set(_ newValue: T) {
        lock.withLock {
            value = newValue
        }
    }
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

    nonisolated func withLock<T>(_ body: @Sendable () -> T) -> T {
        lock.withLock(body)
    }

    nonisolated func updateDefaultOutputDeviceID(_ id: AudioDeviceID) {
        withLock { defaultOutputDeviceID = id }
    }

    nonisolated func defaultOutputDeviceIDValue() -> AudioDeviceID {
        withLock { defaultOutputDeviceID }
    }

    nonisolated func updateListeningDeviceID(_ id: AudioDeviceID?) {
        withLock { listeningDeviceID = id }
    }

    nonisolated func listeningDeviceIDValue() -> AudioDeviceID? {
        withLock { listeningDeviceID }
    }

    nonisolated func updateVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { volumeElements = elements }
    }

    nonisolated func volumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { volumeElements }
    }

    nonisolated func updateMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { muteElements = elements }
    }

    nonisolated func muteElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { muteElements }
    }

    nonisolated func updateRegisteredVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { registeredVolumeElements = elements }
    }

    nonisolated func registeredVolumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { registeredVolumeElements }
    }

    nonisolated func updateRegisteredMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { registeredMuteElements = elements }
    }

    nonisolated func registeredMuteElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { registeredMuteElements }
    }

    nonisolated func setDeviceMuted(_ muted: Bool) {
        withLock { isDeviceMuted = muted }
    }

    nonisolated func deviceMuted() -> Bool {
        withLock { isDeviceMuted }
    }

    nonisolated func updateLastVolumeScalar(_ scalar: CGFloat?) {
        withLock { lastVolumeScalar = scalar }
    }

    nonisolated func lastVolumeScalarSnapshot() -> CGFloat? {
        withLock { lastVolumeScalar }
    }

    nonisolated func setListeningActive(_ active: Bool) {
        withLock { isListening = active }
    }

    nonisolated func isListeningActive() -> Bool {
        withLock { isListening }
    }
}

@MainActor
class VolumeMonitor: ObservableObject {
    @Published var volumePercentage: Int = 0
    @Published var audioDevices: [AudioDevice] = []
    @Published var currentDevice: AudioDevice?
    @Published var isCurrentDeviceVolumeSupported: Bool = false

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

    nonisolated private var volumeListener: AudioObjectPropertyListenerBlock? {
        get { volumeListenerProperty.get() }
        set { volumeListenerProperty.set(newValue) }
    }

    nonisolated private var deviceListener: AudioObjectPropertyListenerBlock? {
        get { deviceListenerProperty.get() }
        set { deviceListenerProperty.set(newValue) }
    }

    nonisolated private var muteListener: AudioObjectPropertyListenerBlock? {
        get { muteListenerProperty.get() }
        set { muteListenerProperty.set(newValue) }
    }

    private nonisolated let audioQueue: DispatchQueue = DispatchQueue(
        label: "com.volumegrid.audio", qos: .userInitiated
    )
    private nonisolated let volumeListenerProperty:
        ThreadSafeProperty<AudioObjectPropertyListenerBlock?> =
            ThreadSafeProperty(nil)
    private nonisolated let deviceListenerProperty:
        ThreadSafeProperty<AudioObjectPropertyListenerBlock?> =
            ThreadSafeProperty(nil)
    private nonisolated let muteListenerProperty:
        ThreadSafeProperty<AudioObjectPropertyListenerBlock?> =
            ThreadSafeProperty(nil)

    nonisolated private func makePropertyAddress(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        .init(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

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
        }
    }

    nonisolated var hudEvents: AnyPublisher<HUDEvent, Never> {
        hudEventSubject.eraseToAnyPublisher()
    }

    @discardableResult
    private nonisolated func updateDefaultOutputDevice() -> AudioDeviceID {
        let deviceID = deviceManager.getDefaultOutputDevice()
        state.updateDefaultOutputDeviceID(deviceID)
        return deviceID
    }

    func getAudioDevices() {
        let devices = deviceManager.getAllDevices()
        let resolvedID = resolveDeviceID()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioDevices = devices
            if resolvedID != 0, let currentDevice = devices.first(where: { $0.id == resolvedID }) {
                self.currentDevice = currentDevice
            }
        }
    }

    nonisolated func getCurrentVolume() -> Float32? {
        let deviceID = resolveDeviceID()
        guard deviceID != 0 else { return nil }

        let elements = deviceManager.detectVolumeElements(for: deviceID)
        guard !elements.isEmpty else { return nil }

        state.updateVolumeElements(elements)
        return deviceManager.getCurrentVolume(for: deviceID, elements: elements)
    }

    func setVolume(percentage: Int) {
        setVolume(scalar: Float32(percentage.clamped(to: 0...100)) / 100.0)
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
        let muted = deviceManager.getMuteState(for: resolvedDeviceID, elements: elements) ?? false
        state.setDeviceMuted(muted)
        if muted {
            volumePercentage = 0
        } else {
            // When unmuting, set volumePercentage to the actual current volume
            if let volume = getCurrentVolume() {
                volumePercentage = Int(round(volume * 100))
            }
        }
        return muted ? true : nil
    }

    private func volumeChanged(address _: AudioObjectPropertyAddress) {
        guard let volume = getCurrentVolume() else { return }

        let clampedVolume = volume.clamped(to: 0...1)
        let percentage = Int(round(clampedVolume * 100))
        let currentScalar = CGFloat(clampedVolume)
        let previousScalar = state.lastVolumeScalarSnapshot()

        let shouldShowHUD: Bool
        if let previousScalar {
            let delta = abs(previousScalar - currentScalar)
            let isAtBoundary =
                (currentScalar <= volumeEpsilon && previousScalar <= volumeEpsilon)
                || (currentScalar >= (1 - volumeEpsilon) && previousScalar >= (1 - volumeEpsilon))
            shouldShowHUD = delta > volumeEpsilon || isAtBoundary
        } else {
            shouldShowHUD = true
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.updateLastVolumeScalar(currentScalar)
            self.volumePercentage = percentage

            if currentScalar > volumeEpsilon, self.state.deviceMuted() {
                self.state.setDeviceMuted(false)
            }

            if shouldShowHUD {
                self.volumeChangeDebouncer?.cancel()
                let capturedScalar = currentScalar
                let debouncer = DispatchWorkItem { [weak self] in
                    self?.showVolumeHUD(volumeScalar: capturedScalar)
                }
                self.volumeChangeDebouncer = debouncer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: debouncer)
            }
        }
    }

    private func muteChanged(address _: AudioObjectPropertyAddress) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wasMuted = self.state.deviceMuted()
            _ = self.refreshMuteState()
            let isNowMuted = self.state.deviceMuted()
            if wasMuted != isNowMuted {
                self.showVolumeHUD(
                    volumeScalar: isNowMuted ? 0 : CGFloat(self.volumePercentage) / 100.0)
            }
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
                var volumeAddress = makePropertyAddress(
                    kAudioDevicePropertyVolumeScalar, element: element)

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
                        var muteAddress = makePropertyAddress(
                            kAudioDevicePropertyMute, element: element)

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
                var volumeAddress = makePropertyAddress(
                    kAudioDevicePropertyVolumeScalar, element: element)
                if removalDeviceID != 0 {
                    AudioObjectRemovePropertyListenerBlock(
                        removalDeviceID, &volumeAddress, audioQueue, volumeListener)
                }
            }
        }

        if let muteListener = muteListener {
            let registeredMutes = state.registeredMuteElementsSnapshot()
            for element in registeredMutes {
                var muteAddress = makePropertyAddress(kAudioDevicePropertyMute, element: element)
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

    private func emitHUDEvent(volumeScalar: CGFloat, isUnsupported: Bool) {
        let event = HUDEvent(
            volumeScalar: volumeScalar,
            deviceName: currentDevice?.name,
            isUnsupported: isUnsupported
        )

        hudEventSubject.send(event)
    }

    private func updateVolumeSupportState(_ isSupported: Bool) {
        isCurrentDeviceVolumeSupported = isSupported
        if !isSupported {
            state.updateLastVolumeScalar(0)
            if volumePercentage != 0 {
                volumePercentage = 0
            }
        }
    }
}
