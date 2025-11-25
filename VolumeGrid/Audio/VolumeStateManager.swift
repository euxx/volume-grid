import AudioToolbox
import Foundation

/// Thread-safe state container using Swift Actors instead of manual locking
/// This actor manages the shared state for volume monitoring across threads
actor VolumeStateManager: Sendable {
    var defaultOutputDeviceID: AudioDeviceID = 0
    var listeningDeviceID: AudioDeviceID?
    var volumeElements: [AudioObjectPropertyElement] = []
    var muteElements: [AudioObjectPropertyElement] = []
    var registeredVolumeElements: [AudioObjectPropertyElement] = []
    var registeredMuteElements: [AudioObjectPropertyElement] = []
    var lastVolumeScalar: CGFloat?
    var isDeviceMuted = false
    var isListening = false

    /// Create a snapshot of current state for inspection
    func getSnapshot() -> VolumeStateSnapshot {
        VolumeStateSnapshot(
            defaultOutputDeviceID: defaultOutputDeviceID,
            listeningDeviceID: listeningDeviceID,
            volumeElements: volumeElements,
            muteElements: muteElements,
            registeredVolumeElements: registeredVolumeElements,
            registeredMuteElements: registeredMuteElements,
            lastVolumeScalar: lastVolumeScalar,
            isDeviceMuted: isDeviceMuted,
            isListening: isListening
        )
    }
}

/// Immutable snapshot of volume state, safe to pass between threads
struct VolumeStateSnapshot: Sendable {
    let defaultOutputDeviceID: AudioDeviceID
    let listeningDeviceID: AudioDeviceID?
    let volumeElements: [AudioObjectPropertyElement]
    let muteElements: [AudioObjectPropertyElement]
    let registeredVolumeElements: [AudioObjectPropertyElement]
    let registeredMuteElements: [AudioObjectPropertyElement]
    let lastVolumeScalar: CGFloat?
    let isDeviceMuted: Bool
    let isListening: Bool
}
