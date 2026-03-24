import SwiftUI

@MainActor
struct SmartVolumeSettingsView: View {
    @ObservedObject private var settings = SmartVolumeSettings.shared
    private let coordinator: SmartVolumeCoordinator?

    init(coordinator: SmartVolumeCoordinator? = nil) {
        self.coordinator = coordinator
    }

    private let totalBars = VolumeGridConstants.volumeBlocksCount

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Volume Grid Range") {
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow(
                        label: "Minimum",
                        valueText: "\(bars(settings.minVolume)) bars",
                        slider: Slider(
                            value: Binding(
                                get: { settings.minVolume },
                                set: {
                                    let snapped = snapToBlock($0)
                                    settings.minVolume = min(snapped, settings.maxVolume)
                                }
                            ),
                            in: 0...1
                        )
                    )
                    sliderRow(
                        label: "Maximum",
                        valueText: "\(bars(settings.maxVolume)) bars",
                        slider: Slider(
                            value: Binding(
                                get: { settings.maxVolume },
                                set: {
                                    let snapped = snapToBlock($0)
                                    settings.maxVolume = max(snapped, settings.minVolume)
                                }
                            ),
                            in: 0...1
                        )
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Target Loudness") {
                VStack(alignment: .leading, spacing: 8) {
                    sliderRow(
                        label: "Target",
                        valueText: String(
                            format: "%.0f%% · %@", settings.targetRMS * 100,
                            loudnessLabel(settings.targetRMS)),
                        slider: Slider(value: $settings.targetRMS, in: 0.01...0.30)
                    )
                    Text(
                        "Higher = louder content is the baseline. Lower = AGC boosts quiet content more. "
                            + "Try 5% for muted videos, 10–15% for normal speech/video."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    if let coordinator {
                        CalibrateButton(coordinator: coordinator)
                    }
                    Divider()
                    sliderRow(
                        label: "Strength",
                        valueText: String(format: "%.0f%%", settings.strength * 100),
                        slider: Slider(value: $settings.strength, in: 0...1)
                    )
                    Text(
                        "100% = full normalisation. Lower values preserve more original dynamics "
                            + "when content varies widely in loudness."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Response Speed") {
                VStack(alignment: .leading, spacing: 8) {
                    sliderRow(
                        label: "Speed",
                        valueText: String(
                            format: "↓%.1fs  ↑%.0fs",
                            settings.attackSeconds, settings.releaseSeconds),
                        slider: Slider(value: $settings.smoothing, in: 0...1)
                    )
                    Text(
                        "↓ How fast volume drops when audio gets louder. "
                            + "↑ How fast volume rises when audio gets quieter."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(width: 360)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sliderRow(label: String, valueText: String, slider: some View) -> some View {
        HStack {
            Text(label)
                .frame(width: 60, alignment: .leading)
            slider
            Text(valueText)
                .frame(width: 90, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func bars(_ scalar: Float) -> Int {
        Int(round(scalar * Float(totalBars)))
    }

    /// Snap a [0,1] slider value to the nearest full-block boundary (multiples of 1/16),
    /// so the settings label and the HUD both show a whole-number block count.
    private func snapToBlock(_ scalar: Float) -> Float {
        (scalar * Float(totalBars)).rounded() / Float(totalBars)
    }

    private func loudnessLabel(_ rms: Float) -> String {
        switch rms {
        case ..<0.04: return "quiet"
        case ..<0.09: return "soft"
        case ..<0.16: return "normal"
        default: return "loud"
        }
    }
}

/// Observe coordinator state so the button reflects live isRunning / lastMeasuredRMS changes.
@MainActor
private struct CalibrateButton: View {
    @ObservedObject var coordinator: SmartVolumeCoordinator

    var body: some View {
        HStack {
            Button("Calibrate to Current Loudness") {
                coordinator.calibrateTargetRMS()
            }
            .disabled(!coordinator.isRunning || coordinator.lastMeasuredRMS == nil)
            Spacer()
            Text(
                coordinator.isRunning
                    ? "Sets target to what you're hearing now" : "Start Smart Volume first"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
