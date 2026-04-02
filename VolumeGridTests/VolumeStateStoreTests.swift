import XCTest
import os.lock

@testable import VolumeGrid

// MARK: - VolumeStateStore Version-Token Tests

final class VolumeStateStoreTests: XCTestCase {

    func testPreUpdateIncrementsVersion() {
        let store = VolumeStateStore()
        let (_, token1) = store.preUpdateLastVolumeScalar(0.5)
        let (_, token2) = store.preUpdateLastVolumeScalar(0.6)
        XCTAssertEqual(token2, token1 + 1)
    }

    func testPreUpdateReturnsCorrectPrevious() {
        let store = VolumeStateStore()
        store.updateLastVolumeScalar(0.3)

        let (previous, _) = store.preUpdateLastVolumeScalar(0.7)
        XCTAssertEqual(previous, 0.3)
    }

    func testPreUpdateReturnsNilPreviousWhenUnset() {
        let store = VolumeStateStore()
        let (previous, _) = store.preUpdateLastVolumeScalar(0.5)
        XCTAssertNil(previous)
    }

    func testRevertSucceedsWithMatchingToken() {
        let store = VolumeStateStore()
        store.updateLastVolumeScalar(0.3)

        let (previous, token) = store.preUpdateLastVolumeScalar(0.8)
        XCTAssertEqual(store.lastVolumeScalarSnapshot(), 0.8)

        store.revertLastVolumeScalar(version: token, to: previous)
        XCTAssertEqual(store.lastVolumeScalarSnapshot(), 0.3)
    }

    func testRevertNoOpsWithMismatchedToken() {
        let store = VolumeStateStore()
        store.updateLastVolumeScalar(0.3)

        let (_, oldToken) = store.preUpdateLastVolumeScalar(0.5)
        // A newer write invalidates the old token
        let (_, _) = store.preUpdateLastVolumeScalar(0.9)

        store.revertLastVolumeScalar(version: oldToken, to: 0.3)
        // Should NOT revert because a newer pre-update exists
        XCTAssertEqual(store.lastVolumeScalarSnapshot(), 0.9)
    }

    func testMultiplePreUpdatesOnlyNewestReverts() {
        let store = VolumeStateStore()
        store.updateLastVolumeScalar(0.2)

        let (_, _) = store.preUpdateLastVolumeScalar(0.4)
        let (_, _) = store.preUpdateLastVolumeScalar(0.6)
        let (prev3, token3) = store.preUpdateLastVolumeScalar(0.8)

        // Only the latest token should allow revert
        store.revertLastVolumeScalar(version: token3, to: prev3)
        XCTAssertEqual(store.lastVolumeScalarSnapshot(), 0.6)
    }

    func testUpdateLastVolumeScalarBumpsVersion() {
        let store = VolumeStateStore()
        let (_, token1) = store.preUpdateLastVolumeScalar(0.3)
        store.updateLastVolumeScalar(0.5)  // bumps version
        let (_, token2) = store.preUpdateLastVolumeScalar(0.7)

        // Version should have been bumped by updateLastVolumeScalar too
        XCTAssertGreaterThan(token2, token1)
    }

    func testRevertWithStaleTokenAfterUpdateLastVolumeScalar() {
        let store = VolumeStateStore()
        let (_, token) = store.preUpdateLastVolumeScalar(0.5)
        store.updateLastVolumeScalar(0.8)  // bumps version, invalidates token

        store.revertLastVolumeScalar(version: token, to: 0.0)
        // Should NOT revert
        XCTAssertEqual(store.lastVolumeScalarSnapshot(), 0.8)
    }

    // MARK: - Basic state accessors

    func testDeviceMutedDefaultsFalse() {
        let store = VolumeStateStore()
        XCTAssertFalse(store.deviceMuted())
    }

    func testSetDeviceMuted() {
        let store = VolumeStateStore()
        store.setDeviceMuted(true)
        XCTAssertTrue(store.deviceMuted())
        store.setDeviceMuted(false)
        XCTAssertFalse(store.deviceMuted())
    }

    func testListeningActiveDefaultsFalse() {
        let store = VolumeStateStore()
        XCTAssertFalse(store.isListeningActive())
    }

    func testSetListeningActive() {
        let store = VolumeStateStore()
        store.setListeningActive(true)
        XCTAssertTrue(store.isListeningActive())
    }

    func testDefaultOutputDeviceID() {
        let store = VolumeStateStore()
        XCTAssertEqual(store.defaultOutputDeviceIDValue(), 0)
        store.updateDefaultOutputDeviceID(42)
        XCTAssertEqual(store.defaultOutputDeviceIDValue(), 42)
    }

    // MARK: - Concurrent access

    func testConcurrentPreUpdateAndRevert() {
        let store = VolumeStateStore()
        store.updateLastVolumeScalar(0.5)

        let queue = DispatchQueue.global()
        let group = DispatchGroup()
        let iterations = 200

        // Concurrent pre-updates from multiple threads
        for i in 0..<iterations {
            group.enter()
            queue.async {
                let scalar = CGFloat(i) / CGFloat(iterations)
                let (prev, token) = store.preUpdateLastVolumeScalar(scalar)
                // Try to revert half the time
                if i % 2 == 0 {
                    store.revertLastVolumeScalar(version: token, to: prev)
                }
                group.leave()
            }
        }

        group.wait()

        // Should not crash or produce invalid state
        let finalSnapshot = store.lastVolumeScalarSnapshot()
        XCTAssertNotNil(finalSnapshot)
    }
}
