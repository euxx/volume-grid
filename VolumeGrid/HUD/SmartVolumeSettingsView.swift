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
                    if let coordinator {
                        Divider()
                        LiveVolumeIndicator(coordinator: coordinator)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Comfort Zone") {
                VStack(alignment: .leading, spacing: 8) {
                    sliderRow(
                        label: "Too loud",
                        valueText: String(
                            format: "%.0f%% · %@", settings.targetRMSHigh * 100,
                            loudnessLabel(settings.targetRMSHigh)),
                        slider: Slider(value: $settings.targetRMSHigh, in: 0.01...0.30)
                    )
                    sliderRow(
                        label: "Too quiet",
                        valueText: String(
                            format: "%.0f%% · %@", settings.targetRMSLow * 100,
                            loudnessLabel(settings.targetRMSLow)),
                        slider: Slider(value: $settings.targetRMSLow, in: 0.01...0.30)
                    )
                    Text(
                        "AGC only acts outside this range. Set ‘Too loud’ to your preferred maximum "
                            + "listening level; ‘Too quiet’ to the minimum acceptable level. "
                            + "Tap Calibrate to set both bounds relative to your current listening volume."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    if let coordinator {
                        if #available(macOS 14.2, *) {
                            SilenceIndicator(coordinator: coordinator)
                        }
                        CalibrateButton(coordinator: coordinator)
                    }
                    Divider()
                    sliderRow(
                        label: "Strength",
                        valueText: String(format: "%.0f%%", settings.strength * 100),
                        slider: Slider(value: $settings.strength, in: 0...1)
                    )
                    Text(
                        "100% = full normalisation at zone boundary. Lower values apply gentler correction."
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
private struct LiveVolumeIndicator: View {
    @ObservedObject var coordinator: SmartVolumeCoordinator

    var body: some View {
        HStack {
            Text("Current")
                .frame(width: 60, alignment: .leading)
            Spacer()
            Text(
                VolumeFormatter.formattedVolumeString(forScalar: CGFloat(coordinator.currentVolume))
                    + " bars"
            )
            .frame(width: 90, alignment: .trailing)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}

/// Observe coordinator state so the button reflects live isRunning / lastMeasuredRMS changes.
@MainActor
private struct CalibrateButton: View {
    @ObservedObject var coordinator: SmartVolumeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Calibrate to Current Loudness") {
                coordinator.calibrateTargetRMS()
            }
            .disabled(!coordinator.isRunning || coordinator.lastMeasuredRMS == nil)
            Text(
                coordinator.isRunning
                    ? "Centers comfort zone around current listening level"
                    : "Start Smart Volume first"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Shows whether SoundAnalysis currently classifies the signal as silence.
/// This is the only scene-detection state that affects AGC behaviour.
@available(macOS 14.2, *)
@MainActor
private struct SilenceIndicator: View {
    @ObservedObject var coordinator: SmartVolumeCoordinator

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isSilent: Bool { coordinator.silenceConfidence > 0.5 }

    private var label: String {
        guard coordinator.isRunning else { return "Start Smart Volume to enable detection" }
        if coordinator.topClassifications.isEmpty { return "Detecting…" }
        if isSilent {
            return String(
                format: "Silence detected (%.0f%%) — AGC raise paused",
                coordinator.silenceConfidence * 100)
        }
        return "Audio active — AGC running"
    }

    private var dotColor: Color {
        guard coordinator.isRunning, !coordinator.topClassifications.isEmpty else {
            return .secondary
        }
        return isSilent ? .orange : .green
    }
}
