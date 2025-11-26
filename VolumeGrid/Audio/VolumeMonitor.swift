import AudioToolbox
import Cocoa
@preconcurrency import Combine
import os
@preconcurrency import os.lock

private let logger = Logger(subsystem: "com.volumegrid", category: "VolumeMonitor")

struct HUDEvent {
    let volumeScalar: CGFloat
    let deviceName: String?
    let isUnsupported: Bool
}

/// Generic thread-safe property wrapper using OSAllocatedUnfairLock
/// This provides lock-based thread-safety for closures and listeners that need to be
/// stored and accessed from multiple threads, particularly from CoreAudio callbacks.
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

/// Internal state for VolumeMonitor
/// Contains mutable state that must be accessed safely from multiple threads
private struct VolumeState {
    var defaultOutputDeviceID: AudioDeviceID = 0
    var listeningDeviceID: AudioDeviceID?
    var volumeElements: [AudioObjectPropertyElement] = []
    var muteElements: [AudioObjectPropertyElement] = []
    var registeredVolumeElements: [AudioObjectPropertyElement] = []
    var registeredMuteElements: [AudioObjectPropertyElement] = []
    var lastVolumeScalar: CGFloat?
    var isDeviceMuted = false
    var isListening = false
}

/// Thread-safe container for volume state using unfair lock
/// Uses manual locking because:
/// - VolumeMonitor is @MainActor but needs background thread access
/// - CoreAudio callbacks occur on arbitrary threads
/// - Actor would require await at too many call sites
private final class VolumeStateStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private nonisolated(unsafe) var state = VolumeState()

    nonisolated init() {}

    nonisolated func withLock<T>(_ body: @Sendable (inout VolumeState) -> T) -> T {
        lock.withLock {
            body(&state)
        }
    }

    nonisolated func defaultOutputDeviceIDValue() -> AudioDeviceID {
        withLock { $0.defaultOutputDeviceID }
    }

    nonisolated func updateDefaultOutputDeviceID(_ id: AudioDeviceID) {
        withLock { $0.defaultOutputDeviceID = id }
    }

    nonisolated func listeningDeviceIDValue() -> AudioDeviceID? {
        withLock { $0.listeningDeviceID }
    }

    nonisolated func updateListeningDeviceID(_ id: AudioDeviceID?) {
        withLock { $0.listeningDeviceID = id }
    }

    nonisolated func volumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { $0.volumeElements }
    }

    nonisolated func updateVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { $0.volumeElements = elements }
    }

    nonisolated func muteElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { $0.muteElements }
    }

    nonisolated func updateMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { $0.muteElements = elements }
    }

    nonisolated func registeredVolumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { $0.registeredVolumeElements }
    }

    nonisolated func updateRegisteredVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { $0.registeredVolumeElements = elements }
    }

    nonisolated func registeredMuteElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { $0.registeredMuteElements }
    }

    nonisolated func updateRegisteredMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { $0.registeredMuteElements = elements }
    }

    nonisolated func deviceMuted() -> Bool {
        withLock { $0.isDeviceMuted }
    }

    nonisolated func setDeviceMuted(_ muted: Bool) {
        withLock { $0.isDeviceMuted = muted }
    }

    nonisolated func lastVolumeScalarSnapshot() -> CGFloat? {
        withLock { $0.lastVolumeScalar }
    }

    nonisolated func updateLastVolumeScalar(_ scalar: CGFloat?) {
        withLock { $0.lastVolumeScalar = scalar }
    }

    nonisolated func isListeningActive() -> Bool {
        withLock { $0.isListening }
    }

    nonisolated func setListeningActive(_ active: Bool) {
        withLock { $0.isListening = active }
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
    private nonisolated let hudEventSubject = PassthroughSubject<HUDEvent, Never>()
    private var volumeChangeDebounceTask: Task<Void, Never>?
    private var deviceChangeDebounceTask: Task<Void, Never>?

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

    init() {
        let deviceID = updateDefaultOutputDevice()
        isCurrentDeviceVolumeSupported =
            deviceID != 0 && deviceManager.supportsVolumeControl(deviceID)
        logger.debug(
            "VolumeMonitor initialized: deviceID=\(deviceID, privacy: .public), supportsVolume=\(self.isCurrentDeviceVolumeSupported, privacy: .public)"
        )
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
        // Cancel any pending debounce tasks to prevent them from executing after deinit
        volumeChangeDebounceTask?.cancel()
        deviceChangeDebounceTask?.cancel()

        // CRITICAL: Ensure CoreAudio listeners are removed before deallocation
        // Must use strong references to dependencies to guarantee cleanup even if deinit runs on background thread
        let state = self.state
        let deviceManager = self.deviceManager
        let audioQueue = self.audioQueue
        let systemEventMonitor = self.systemEventMonitor
        let volumeListener = self.volumeListener
        let muteListener = self.muteListener
        let deviceListener = self.deviceListener

        // Always dispatch to main thread for @MainActor performCleanup
        DispatchQueue.main.async {
            Self.performCleanup(
                state: state,
                deviceManager: deviceManager,
                audioQueue: audioQueue,
                systemEventMonitor: systemEventMonitor,
                volumeListener: volumeListener,
                muteListener: muteListener,
                deviceListener: deviceListener
            )
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
            guard deviceID != 0 else {
                logger.debug("setVolume: Device ID is 0, cannot set volume")
                return
            }

            let elements = self.state.volumeElementsSnapshot()
            guard !elements.isEmpty else {
                logger.debug("setVolume: No volume elements found for device")
                return
            }

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
        // Only show HUD when volume actually changes (triggered by volume key press or real API change)
        guard let volume = getCurrentVolume() else { return }

        let clampedVolume = volume.clamped(to: 0...1)
        let percentage = Int(round(clampedVolume * 100))
        let currentScalar = CGFloat(clampedVolume)
        let epsilon = VolumeGridConstants.Audio.volumeEpsilon

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let lastScalar = self.state.lastVolumeScalarSnapshot() ?? 0
            let volumeActuallyChanged = abs(currentScalar - lastScalar) > epsilon
            if !volumeActuallyChanged {
                return
            }
            self.state.updateLastVolumeScalar(currentScalar)
            self.volumePercentage = percentage
            if currentScalar > epsilon, self.state.deviceMuted() {
                logger.debug("volumeChanged: Volume > 0 but device is muted, unmuting")
                self.state.setDeviceMuted(false)
            }

            self.volumeChangeDebounceTask?.cancel()
            let task = Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        VolumeGridConstants.Audio.volumeChangeDebounceDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                let finalScalar = self.state.lastVolumeScalarSnapshot() ?? currentScalar
                self.showVolumeHUD(volumeScalar: finalScalar)
            }
            self.volumeChangeDebounceTask = task
        }
    }

    private func muteChanged(address _: AudioObjectPropertyAddress) {
        // CoreAudio can fire mute callbacks even when state doesn't change (e.g., browser video resolution change)
        // Only show HUD when mute state actually changes to avoid spurious displays
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wasMuted = self.state.deviceMuted()
            let previousVolumeScalar =
                self.state.lastVolumeScalarSnapshot() ?? CGFloat(self.volumePercentage) / 100.0
            _ = self.refreshMuteState()
            let isNowMuted = self.state.deviceMuted()

            // Only display HUD if mute state actually changed
            if wasMuted != isNowMuted {
                logger.debug("muteChanged: Mute state changed from \(wasMuted) to \(isNowMuted)")
                let displayScalar = isNowMuted ? 0 : previousVolumeScalar
                self.showVolumeHUD(volumeScalar: displayScalar)
            }
        }
    }

    private func deviceChanged() {
        deviceChangeDebounceTask?.cancel()
        let task = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(
                    VolumeGridConstants.Audio.deviceChangeDebounceDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            self.stopListening()
            self.updateDefaultOutputDevice()
            self.getAudioDevices()
            self.startListening()

            let currentOutputID = self.state.defaultOutputDeviceIDValue()
            if currentOutputID != 0 {
                if let current = self.audioDevices.first(where: { $0.id == currentOutputID }) {
                    self.currentDevice = current
                } else if let name = self.deviceManager.getDeviceName(currentOutputID) {
                    self.currentDevice = AudioDevice(id: currentOutputID, name: name)
                } else {
                    self.currentDevice = nil
                }
            } else {
                self.currentDevice = nil
            }
            self.updateVolumeSupportState(
                currentOutputID != 0 && self.deviceManager.supportsVolumeControl(currentOutputID))
            let deviceName = self.currentDevice?.name ?? "Unknown"
            logger.debug(
                "deviceChanged: New device - id=\(currentOutputID, privacy: .public), name=\(deviceName, privacy: .public), supportsVolume=\(self.isCurrentDeviceVolumeSupported, privacy: .public)"
            )

            if currentOutputID != 0 && self.deviceManager.supportsVolumeControl(currentOutputID) {
                _ = self.refreshMuteState()
            }

            if let volume = self.getCurrentVolume() {
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
        deviceChangeDebounceTask = task
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
            let isMuted = state.deviceMuted()
            scalar = isMuted ? 0 : CGFloat(clamped)
            state.updateLastVolumeScalar(CGFloat(clamped))
            volumePercentage = isMuted ? 0 : Int(round(clamped * 100))
            isUnsupported = false
        } else {
            scalar = state.lastVolumeScalarSnapshot() ?? 0
            isUnsupported = true
        }

        // Always show HUD when mute/volume key is pressed, regardless of whether state changed
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
                guard let self = self, self.state.isListeningActive() else { return }
                self.volumeChanged(address: inAddresses.pointee)
            }

            guard let volumeListener = volumeListener else { return }

            var listenerRegistered = false
            let volumeElementsSnapshot = state.volumeElementsSnapshot()
            for element in volumeElementsSnapshot {
                var volumeAddress = deviceManager.makePropertyAddress(
                    selector: kAudioDevicePropertyVolumeScalar, element: element)

                let volumeStatus = AudioObjectAddPropertyListenerBlock(
                    deviceID, &volumeAddress, audioQueue, volumeListener)
                if volumeStatus == noErr {
                    listenerRegistered = true
                }
            }

            guard listenerRegistered else {
                logger.debug("startListening: No volume listeners were registered")
                return
            }
            state.updateRegisteredVolumeElements(volumeElementsSnapshot)

            let muteElementsSnapshot = state.muteElementsSnapshot()
            if !muteElementsSnapshot.isEmpty {
                muteListener = {
                    [weak self] (_: UInt32, inAddresses: UnsafePointer<AudioObjectPropertyAddress>)
                    in
                    guard let self = self, self.state.isListeningActive() else { return }
                    self.muteChanged(address: inAddresses.pointee)
                }

                if let muteListener = muteListener {
                    var validMuteElements: [AudioObjectPropertyElement] = []
                    for element in muteElementsSnapshot {
                        var muteAddress = deviceManager.makePropertyAddress(
                            selector: kAudioDevicePropertyMute, element: element)

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

        // Key press handler: always show HUD when user presses volume/mute keys
        systemEventMonitor.start { [weak self] in
            guard let self else { return }
            if self.isCurrentDeviceVolumeSupported {
                self.showHUDForCurrentVolume()
            } else {
                let fallbackScalar = self.state.lastVolumeScalarSnapshot() ?? 0
                logger.debug(
                    "startListening: Device doesn't support volume control, showing unsupported HUD"
                )
                self.showVolumeHUD(volumeScalar: fallbackScalar, isUnsupported: true)
            }
        }

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        deviceListener = { [weak self] (_: UInt32, _: UnsafePointer<AudioObjectPropertyAddress>) in
            guard let self = self, self.state.isListeningActive() else { return }
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

    @MainActor
    private static func performCleanup(
        state: VolumeStateStore,
        deviceManager: AudioDeviceManager,
        audioQueue: DispatchQueue,
        systemEventMonitor: SystemEventMonitor,
        volumeListener: AudioObjectPropertyListenerBlock?,
        muteListener: AudioObjectPropertyListenerBlock?,
        deviceListener: AudioObjectPropertyListenerBlock?
    ) {
        // CRITICAL: This method uses strong references to all dependencies.
        // Even if the VolumeMonitor instance has been deallocated, these strong references
        // keep the required objects alive long enough to safely remove CoreAudio listeners.
        // This prevents memory leaks when deinit runs on background threads.

        // Stop system event monitor on main thread
        MainActor.assumeIsolated {
            systemEventMonitor.stop()
        }

        // Remove CoreAudio listeners
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        let removalDeviceID =
            state.listeningDeviceIDValue() ?? deviceManager.getDefaultOutputDevice()

        if let volumeListener = volumeListener {
            let registeredVolumes = state.registeredVolumeElementsSnapshot()
            for element in registeredVolumes {
                var volumeAddress = deviceManager.makePropertyAddress(
                    selector: kAudioDevicePropertyVolumeScalar, element: element)
                if removalDeviceID != 0 {
                    AudioObjectRemovePropertyListenerBlock(
                        removalDeviceID, &volumeAddress, audioQueue, volumeListener)
                }
            }
        }

        if let muteListener = muteListener {
            let registeredMutes = state.registeredMuteElementsSnapshot()
            for element in registeredMutes {
                var muteAddress = deviceManager.makePropertyAddress(
                    selector: kAudioDevicePropertyMute, element: element)
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

        state.updateListeningDeviceID(nil)
        state.updateRegisteredVolumeElements([])
        state.updateRegisteredMuteElements([])
    }

    func stopListening() {
        // Cancel pending debounce tasks to prevent them from firing after stopping
        volumeChangeDebounceTask?.cancel()
        deviceChangeDebounceTask?.cancel()

        // Disable listening flag immediately to prevent race conditions
        // This ensures startListening() called right after will be blocked by the guard check
        state.setListeningActive(false)

        // Capture dependencies strongly for cleanup
        let state = self.state
        let deviceManager = self.deviceManager
        let audioQueue = self.audioQueue
        let systemEventMonitor = self.systemEventMonitor
        let volumeListener = self.volumeListener
        let muteListener = self.muteListener
        let deviceListener = self.deviceListener

        // Dispatch cleanup to main thread with strong references
        DispatchQueue.main.async { [weak self] in
            Self.performCleanup(
                state: state,
                deviceManager: deviceManager,
                audioQueue: audioQueue,
                systemEventMonitor: systemEventMonitor,
                volumeListener: volumeListener,
                muteListener: muteListener,
                deviceListener: deviceListener
            )
            // Clear instance listener properties to release closures
            self?.volumeListener = nil
            self?.muteListener = nil
            self?.deviceListener = nil
        }
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
