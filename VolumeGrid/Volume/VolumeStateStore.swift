import AudioToolbox
import CoreGraphics

/// Thread-safe store for the mutable audio state VolumeMonitor needs to access off the main thread.
final class VolumeStateStore {
    private let lock = NSLock()

    private var defaultOutputDeviceID: AudioDeviceID = 0
    private var listeningDeviceID: AudioDeviceID?
    private var volumeElements: [AudioObjectPropertyElement] = []
    private var muteElements: [AudioObjectPropertyElement] = []
    private var registeredVolumeElements: [AudioObjectPropertyElement] = []
    private var registeredMuteElements: [AudioObjectPropertyElement] = []
    private var lastVolumeScalar: CGFloat?
    private var isDeviceMuted = false
    private var isListening = false

    // MARK: - Device IDs

    func updateDefaultOutputDeviceID(_ id: AudioDeviceID) {
        withLock { defaultOutputDeviceID = id }
    }

    func defaultOutputDeviceIDValue() -> AudioDeviceID {
        withLock { defaultOutputDeviceID }
    }

    func updateListeningDeviceID(_ id: AudioDeviceID?) {
        withLock { listeningDeviceID = id }
    }

    func listeningDeviceIDValue() -> AudioDeviceID? {
        withLock { listeningDeviceID }
    }

    // MARK: - Volume Elements

    func updateVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { volumeElements = elements }
    }

    func volumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { volumeElements }
    }

    func updateMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { muteElements = elements }
    }

    func muteElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { muteElements }
    }

    func updateRegisteredVolumeElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { registeredVolumeElements = elements }
    }

    func registeredVolumeElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { registeredVolumeElements }
    }

    func updateRegisteredMuteElements(_ elements: [AudioObjectPropertyElement]) {
        withLock { registeredMuteElements = elements }
    }

    func registeredMuteElementsSnapshot() -> [AudioObjectPropertyElement] {
        withLock { registeredMuteElements }
    }

    // MARK: - Volume Muted State

    func setDeviceMuted(_ muted: Bool) {
        withLock { isDeviceMuted = muted }
    }

    func deviceMuted() -> Bool {
        withLock { isDeviceMuted }
    }

    // MARK: - Volume Scalar

    func updateLastVolumeScalar(_ scalar: CGFloat?) {
        withLock { lastVolumeScalar = scalar }
    }

    func lastVolumeScalarSnapshot() -> CGFloat? {
        withLock { lastVolumeScalar }
    }

    // MARK: - Listening flag

    func setListeningActive(_ active: Bool) {
        withLock { isListening = active }
    }

    func isListeningActive() -> Bool {
        withLock { isListening }
    }

    // MARK: - Helpers

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
