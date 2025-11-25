import AudioToolbox
import Foundation
import os

private let logger = Logger(subsystem: "com.volumegrid", category: "VolumeStateActor")

/// Immutable snapshot of volume state for safe cross-thread access
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

/// UI-thread focused Actor for volume state management
/// Provides modern async/await interface for main thread operations
/// Complements the lock-based state store for CoreAudio callback compatibility
actor VolumeStateActor: Sendable {
    var lastVolumeScalar: CGFloat?
    var isDeviceMuted = false

    /// Create actor with initial state
    init() {}

    /// Update volume state from UI thread
    func updateVolumeState(scalar: CGFloat, isMuted: Bool) {
        lastVolumeScalar = scalar
        isDeviceMuted = isMuted
    }

    /// Get current volume state
    func getVolumeState() -> (scalar: CGFloat?, isMuted: Bool) {
        (lastVolumeScalar, isDeviceMuted)
    }

    /// Reset to initial state
    func reset() {
        lastVolumeScalar = nil
        isDeviceMuted = false
    }
}


