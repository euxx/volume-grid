import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var volumeMonitor: VolumeMonitor

    var body: some View {
        VStack {
            Image(systemName: "speaker.wave.2.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("VolumeGrid")
                .font(.headline)
            Text("Current Volume: \(volumeMonitor.volumePercentage)%")
                .font(.title2)
                .padding()

            if let currentDevice = volumeMonitor.currentDevice {
                Text("Current Device: \(currentDevice.name)")
                    .font(.subheadline)
                    .padding(.bottom, 10)
            }
        }
        .padding()
        .onAppear {
            volumeMonitor.startListening()
            volumeMonitor.getAudioDevices()
        }
        .onDisappear {
            volumeMonitor.stopListening()
        }
    }
}
