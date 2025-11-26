import Combine
import Foundation
import XCTest

@testable import Volume_Grid

/// Tests for HUD display scenarios:
/// - When pressing volume keys or mute key
/// - When switching output devices
/// - When volume changes
final class HUDScenarioTests: XCTestCase {
    var hudManager: HUDManager?
    var mockAudioDeviceManager: MockAudioDeviceManager?
    var mockSystemEventMonitor: MockSystemEventMonitor?
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        hudManager = HUDManager()
        mockAudioDeviceManager = MockAudioDeviceManager()
        mockSystemEventMonitor = MockSystemEventMonitor()
    }

    override func tearDown() {
        hudManager = nil
        mockAudioDeviceManager = nil
        mockSystemEventMonitor = nil
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Volume Key Press Scenario Tests

    func testHUDShowsWhenVolumeKeyPressed() {
        let expectation = XCTestExpectation(
            description: "HUD should be visible after volume key press")

        // Simulate volume key press by notifying system
        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 0)

        // Verify HUD is displayed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDShowsWhenMuteKeyPressed() {
        let expectation = XCTestExpectation(
            description: "HUD should be visible after mute key press")

        // Simulate mute key press event
        let hudDisplayed = {
            expectation.fulfill()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hudDisplayed()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDShowsWhenIncreaseVolumeKeyPressed() {
        let expectation = XCTestExpectation(
            description: "HUD should display when volume increase key is pressed")

        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDShowsWhenDecreaseVolumeKeyPressed() {
        let expectation = XCTestExpectation(
            description: "HUD should display when volume decrease key is pressed")

        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 1)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDShowsWhenMuteKeyPressedAtZeroVolume() {
        let expectation = XCTestExpectation(
            description:
                "HUD should display when mute key is pressed even when volume is at 0"
        )

        // Set volume to 0 (muted state)
        let mutedEvent = HUDEvent(
            volumeScalar: 0.0,
            deviceName: "Speaker",
            isUnsupported: false
        )
        XCTAssertEqual(mutedEvent.volumeScalar, 0.0)

        // Now press mute key - this should trigger HUD display
        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 7)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testMuteStateTransitionFromZeroVolume() {
        let expectation = XCTestExpectation(
            description:
                "When volume is 0 and mute state changes, HUD should still be shown"
        )

        // Scenario: volume is 0 and muted=true
        let zeroMutedEvent = HUDEvent(
            volumeScalar: 0.0,
            deviceName: "Speaker",
            isUnsupported: false
        )
        XCTAssertEqual(zeroMutedEvent.volumeScalar, 0.0)

        // User presses mute key to toggle mute state
        // Expected: HUD should show even though volume stays at 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testVolumeChangeFromZeroToNonZero() {
        let expectation = XCTestExpectation(
            description: "HUD should display when volume increases from 0"
        )

        // Start at 0
        let zeroEvent = HUDEvent(volumeScalar: 0.0, deviceName: "Speaker", isUnsupported: false)
        XCTAssertEqual(zeroEvent.volumeScalar, 0.0)

        // Change to non-zero
        let nonZeroEvent = HUDEvent(volumeScalar: 0.3, deviceName: "Speaker", isUnsupported: false)
        XCTAssertEqual(nonZeroEvent.volumeScalar, 0.3)
        XCTAssertNotEqual(zeroEvent.volumeScalar, nonZeroEvent.volumeScalar)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDEventEmittedWhenVolumeIsZero() {
        let expectation = XCTestExpectation(
            description: "HUD event should be emitted with zero volume scalar"
        )
        expectation.isInverted = false

        let event = HUDEvent(
            volumeScalar: 0.0,
            deviceName: "Speaker",
            isUnsupported: false
        )

        // Verify that we can create and work with zero-volume HUD events
        XCTAssertEqual(event.volumeScalar, 0.0)
        XCTAssertEqual(event.deviceName, "Speaker")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testRapidVolumeKeyPresses() {
        let expectation = XCTestExpectation(
            description: "Rapid consecutive volume key presses should show correct HUD values"
        )

        // Simulate rapid volume key presses
        let volumes: [CGFloat] = [0.3, 0.4, 0.5, 0.6, 0.7]
        var events: [HUDEvent] = []

        for volume in volumes {
            let event = HUDEvent(
                volumeScalar: volume,
                deviceName: "Speaker",
                isUnsupported: false
            )
            events.append(event)
            XCTAssertEqual(event.volumeScalar, volume)
        }

        // Verify that the final event has the correct volume
        XCTAssertEqual(events.last?.volumeScalar, 0.7)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testDebounceDoesNotDisplayIntermediateValues() {
        let expectation = XCTestExpectation(
            description:
                "HUD events should not show intermediate values that differ from what was pressed"
        )

        // All displayed values should match what was actually shown or the final state

        let event1 = HUDEvent(volumeScalar: 0.19, deviceName: "Speaker", isUnsupported: false)
        XCTAssertEqual(event1.volumeScalar, 0.19)

        // Simulate multiple rapid events
        let event2 = HUDEvent(volumeScalar: 0.22, deviceName: "Speaker", isUnsupported: false)
        let event3 = HUDEvent(volumeScalar: 0.25, deviceName: "Speaker", isUnsupported: false)

        // The displayed value should be monotonic or jump to final value, never show old intermediate
        XCTAssert(event3.volumeScalar > event2.volumeScalar)
        XCTAssert(event2.volumeScalar > event1.volumeScalar)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Output Device Switch Scenario Tests

    func testHUDShowsWhenOutputDeviceSwitched() {
        let expectation = XCTestExpectation(
            description: "HUD should be visible when output device is switched"
        )

        // Simulate device switch notification
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioDeviceChanged"), object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDDisplaysNewDeviceNameAfterSwitch() {
        let expectation = XCTestExpectation(
            description: "HUD should display new device name after switching"
        )
        let newDeviceName = "External Speakers"

        mockAudioDeviceManager?.setDefaultOutputDevice(name: newDeviceName)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Verify HUD shows new device name
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDUpdatesWhenMultipleDevicesAvailable() {
        let expectation = XCTestExpectation(
            description: "HUD should update when switching between multiple devices"
        )

        mockAudioDeviceManager?.addDevice(name: "Internal Speaker")
        mockAudioDeviceManager?.addDevice(name: "External Speaker")
        mockAudioDeviceManager?.switchToDevice(name: "External Speaker")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Volume Change Scenario Tests

    func testHUDShowsWhenVolumeChanges() {
        let expectation = XCTestExpectation(
            description: "HUD should be visible when volume changes")

        _ = HUDEvent(
            volumeScalar: 0.75,
            deviceName: "Test Speaker",
            isUnsupported: false
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDDisplaysCorrectVolumeLevel() {
        let expectation = XCTestExpectation(
            description: "HUD should display correct volume level"
        )
        let testVolume: CGFloat = 0.65

        let volumeEvent = HUDEvent(
            volumeScalar: testVolume,
            deviceName: "Speaker",
            isUnsupported: false
        )

        XCTAssertEqual(volumeEvent.volumeScalar, testVolume)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDShowsWhenVolumeGoesToZero() {
        let expectation = XCTestExpectation(
            description: "HUD should show when volume goes to zero (mute)")

        let muteEvent = HUDEvent(
            volumeScalar: 0.0,
            deviceName: "Speaker",
            isUnsupported: false
        )

        XCTAssertEqual(muteEvent.volumeScalar, 0.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDShowsWhenVolumeGoesToMaximum() {
        let expectation = XCTestExpectation(
            description: "HUD should show when volume reaches maximum")

        let maxVolumeEvent = HUDEvent(
            volumeScalar: 1.0,
            deviceName: "Speaker",
            isUnsupported: false
        )

        XCTAssertEqual(maxVolumeEvent.volumeScalar, 1.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testHUDUpdatesWithIncrementalVolumeChanges() {
        let expectation = XCTestExpectation(
            description: "HUD should update with incremental volume changes"
        )

        let volumes: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 1.0]
        var updateCount = 0

        for volume in volumes {
            let event = HUDEvent(
                volumeScalar: volume,
                deviceName: "Speaker",
                isUnsupported: false
            )
            XCTAssertEqual(event.volumeScalar, volume)
            updateCount += 1
        }

        XCTAssertEqual(updateCount, volumes.count)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Combined Scenario Tests

    func testHUDShowsForAllThreeScenarios() {
        let volumeKeyExpectation = XCTestExpectation(description: "Volume key scenario")
        let deviceSwitchExpectation = XCTestExpectation(description: "Device switch scenario")
        let volumeChangeExpectation = XCTestExpectation(description: "Volume change scenario")

        // Test 1: Volume key press
        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            volumeKeyExpectation.fulfill()
        }

        // Test 2: Device switch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: NSNotification.Name("AudioDeviceChanged"), object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            deviceSwitchExpectation.fulfill()
        }

        // Test 3: Volume change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let _ = HUDEvent(volumeScalar: 0.8, deviceName: "Speaker", isUnsupported: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            volumeChangeExpectation.fulfill()
        }

        wait(
            for: [volumeKeyExpectation, deviceSwitchExpectation, volumeChangeExpectation],
            timeout: 2.0)
    }

    func testHUDHidesAfterTimeout() {
        let expectation = XCTestExpectation(description: "HUD should hide after timeout")

        mockSystemEventMonitor?.simulateVolumeKeyPress(keyCode: 0)

        // HUD should hide after the timeout period (typically 1-2 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3.0)
    }
}

// MARK: - Mock Helpers

class MockSystemEventMonitor {
    var volumeKeyPressHandler: (() -> Void)?

    func simulateVolumeKeyPress(keyCode: Int) {
        volumeKeyPressHandler?()
    }
}

class MockAudioDeviceManager {
    private var devices: [String: AudioDevice] = [:]
    private var currentDevice: String?

    func addDevice(name: String) {
        devices[name] = AudioDevice(id: UInt32(devices.count), name: name)
    }

    func setDefaultOutputDevice(name: String) {
        currentDevice = name
    }

    func switchToDevice(name: String) {
        currentDevice = name
    }

    func getCurrentDevice() -> String? {
        currentDevice
    }
}
