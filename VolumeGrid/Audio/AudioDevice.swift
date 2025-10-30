import AudioToolbox

// Audio device model.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}
