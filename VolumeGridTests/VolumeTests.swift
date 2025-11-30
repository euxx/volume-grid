import XCTest

@testable import Volume_Grid

// MARK: - Volume Integration Tests

final class VolumeIntegrationTests: XCTestCase {

    // MARK: - Event Creation Pipeline

    func testCompleteEventCreation() {
        let percentage = 50

        let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
        XCTAssertFalse(formatted.isEmpty)

        let icon = VolumeIconHelper.icon(for: percentage)
        XCTAssertFalse(icon.symbolName.isEmpty)

        let event = HUDEvent(
            volumeScalar: CGFloat(percentage) / 100.0,
            deviceName: "Test Device",
            isUnsupported: false
        )

        XCTAssertEqual(event.volumeScalar, 0.5)
        XCTAssertEqual(event.deviceName, "Test Device")
    }

    // MARK: - Unsupported Device Handling

    func testUnsupportedDeviceIcon() {
        let supportedIcon = VolumeIconHelper.icon(for: 50, isUnsupported: false)
        let unsupportedIcon = VolumeIconHelper.icon(for: 50, isUnsupported: true)

        XCTAssertNotEqual(supportedIcon.symbolName, unsupportedIcon.symbolName)
        XCTAssertEqual(unsupportedIcon.symbolName, "nosign")
    }

    func testUnsupportedDeviceEvent() {
        let event = HUDEvent(volumeScalar: 0.5, deviceName: nil, isUnsupported: true)

        XCTAssertTrue(event.isUnsupported)
    }

    // MARK: - Consistency Across Conversions

    func testPercentageToScalarConsistency() {
        let percentage50Formatted = VolumeFormatter.formattedVolumeString(for: 50)
        let scalar050Formatted = VolumeFormatter.formattedVolumeString(forScalar: 0.5)

        XCTAssertEqual(percentage50Formatted, scalar050Formatted)
    }

    func testIconConsistency() {
        let percentage50Icon = VolumeIconHelper.icon(for: 50)
        let percentage49Icon = VolumeIconHelper.icon(for: 49)
        let percentage51Icon = VolumeIconHelper.icon(for: 51)

        XCTAssertEqual(percentage50Icon.symbolName, percentage49Icon.symbolName)
        XCTAssertEqual(percentage50Icon.symbolName, percentage51Icon.symbolName)
    }

    // MARK: - Device Name Integration

    func testEventWithVariousDeviceNames() {
        let deviceNames = [
            "MacBook Pro Speakers",
            "Headphones",
            "USB Audio",
            "HDMI Output",
            "AirPods Pro",
            nil,
        ]

        for deviceName in deviceNames {
            let event = HUDEvent(volumeScalar: 0.5, deviceName: deviceName, isUnsupported: false)

            XCTAssertEqual(event.deviceName, deviceName)
            XCTAssertEqual(event.volumeScalar, 0.5)
        }
    }

    // MARK: - Boundary Conditions

    func testZeroVolumeFullFlow() {
        let formatted = VolumeFormatter.formattedVolumeString(for: 0)
        let icon = VolumeIconHelper.icon(for: 0)
        let event = HUDEvent(volumeScalar: 0.0, deviceName: "Test", isUnsupported: false)

        XCTAssertEqual(formatted, "0")
        XCTAssertEqual(icon.symbolName, "speaker.slash")
        XCTAssertEqual(event.volumeScalar, 0.0)
    }

    func testMaxVolumeFullFlow() {
        let formatted = VolumeFormatter.formattedVolumeString(for: 100)
        let icon = VolumeIconHelper.icon(for: 100)
        let event = HUDEvent(volumeScalar: 1.0, deviceName: "Test", isUnsupported: false)

        XCTAssertEqual(formatted, "16")
        XCTAssertTrue(icon.symbolName.contains("wave.3"))
        XCTAssertEqual(event.volumeScalar, 1.0)
    }
}

// MARK: - Volume Concurrent Access Tests

final class VolumeConcurrentAccessTests: XCTestCase {

    func testConcurrentFormatting() {
        let queue = DispatchQueue.global()
        let group = DispatchGroup()

        var results: [String] = []
        let lock = NSLock()

        for i in 0..<100 {
            group.enter()
            queue.async {
                let formatted = VolumeFormatter.formattedVolumeString(for: i % 101)
                lock.withLock {
                    results.append(formatted)
                }
                group.leave()
            }
        }

        group.wait()

        XCTAssertEqual(results.count, 100)
        XCTAssertTrue(results.allSatisfy { !$0.isEmpty })
    }

    func testConcurrentIconSelection() {
        let queue = DispatchQueue.global()
        let group = DispatchGroup()

        var results: [VolumeIconHelper.VolumeIcon] = []
        let lock = NSLock()

        for i in 0..<100 {
            group.enter()
            queue.async {
                let icon = VolumeIconHelper.icon(for: i % 101)
                lock.withLock {
                    results.append(icon)
                }
                group.leave()
            }
        }

        group.wait()

        XCTAssertEqual(results.count, 100)
        XCTAssertTrue(results.allSatisfy { !$0.symbolName.isEmpty })
    }
}

// MARK: - Performance Tests

final class VolumePerformanceTests: XCTestCase {

    func testFullPipelinePerformance() {
        measure {
            for i in 0...100 {
                let scalar = CGFloat(i) / 100.0

                _ = VolumeFormatter.formattedVolumeString(for: i)
                _ = VolumeFormatter.formattedVolumeString(forScalar: scalar)

                _ = VolumeIconHelper.icon(for: i)
                _ = VolumeIconHelper.hudIcon(for: i)

                _ = HUDEvent(volumeScalar: scalar, deviceName: "Device", isUnsupported: false)
            }
        }
    }
}

// MARK: - Helper Extension

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
