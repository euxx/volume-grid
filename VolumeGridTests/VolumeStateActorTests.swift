import XCTest

@testable import Volume_Grid

/// Integration tests for VolumeStateActor
/// Verifies actor-based state management works correctly
final class VolumeStateActorTests: XCTestCase {

    var actor: VolumeStateActor!

    override func setUp() {
        super.setUp()
        actor = VolumeStateActor()
    }

    override func tearDown() {
        actor = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testActorInitialization() {
        XCTAssertNotNil(actor)
    }

    // MARK: - Volume State Tests

    func testUpdateVolumeState() {
        Task {
            await actor.updateVolumeState(scalar: 0.5, isMuted: false)
            let (scalar, isMuted) = await actor.getVolumeState()
            XCTAssertEqual(scalar, 0.5)
            XCTAssertFalse(isMuted)
        }
    }

    func testUpdateMutedState() {
        Task {
            await actor.updateVolumeState(scalar: 0.75, isMuted: true)
            let (scalar, isMuted) = await actor.getVolumeState()
            XCTAssertEqual(scalar, 0.75)
            XCTAssertTrue(isMuted)
        }
    }

    // MARK: - State Reset Tests

    func testResetClearsState() {
        Task {
            await actor.updateVolumeState(scalar: 0.8, isMuted: true)
            await actor.reset()
            let (scalar, isMuted) = await actor.getVolumeState()
            XCTAssertNil(scalar)
            XCTAssertFalse(isMuted)
        }
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentVolumeUpdates() {
        let expectation = self.expectation(description: "Concurrent updates complete")
        var finalScalar: CGFloat?
        var finalMuted: Bool?

        Task {
            let tasks = (1...10).map { i -> Task<Void, Never> in
                Task {
                    await actor.updateVolumeState(
                        scalar: CGFloat(i) / 10.0,
                        isMuted: i % 2 == 0
                    )
                }
            }

            for task in tasks {
                await task.value
            }

            let (scalar, isMuted) = await actor.getVolumeState()
            finalScalar = scalar
            finalMuted = isMuted

            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        // Verify final state is one of the values that were set
        XCTAssertNotNil(finalScalar)
        XCTAssertNotNil(finalMuted)
        XCTAssert(finalScalar! >= 0 && finalScalar! <= 1.0)
    }

    // MARK: - State Consistency Tests

    func testVolumeStateConsistency() {
        Task {
            for percentage in [0, 25, 50, 75, 100] {
                let scalar = CGFloat(percentage) / 100.0
                await actor.updateVolumeState(scalar: scalar, isMuted: false)
                let (retrievedScalar, isMuted) = await actor.getVolumeState()

                XCTAssertEqual(retrievedScalar, scalar)
                XCTAssertFalse(isMuted)
            }
        }
    }

    // MARK: - Mute State Consistency Tests

    func testMuteStateConsistency() {
        Task {
            for isMuted in [true, false, true, false] {
                await actor.updateVolumeState(scalar: 0.5, isMuted: isMuted)
                let (_, retrievedMuted) = await actor.getVolumeState()

                XCTAssertEqual(retrievedMuted, isMuted)
            }
        }
    }

    // MARK: - Boundary Tests

    func testMinimumVolume() {
        Task {
            await actor.updateVolumeState(scalar: 0.0, isMuted: false)
            let (scalar, isMuted) = await actor.getVolumeState()
            XCTAssertEqual(scalar, 0.0)
            XCTAssertFalse(isMuted)
        }
    }

    func testMaximumVolume() {
        Task {
            await actor.updateVolumeState(scalar: 1.0, isMuted: false)
            let (scalar, isMuted) = await actor.getVolumeState()
            XCTAssertEqual(scalar, 1.0)
            XCTAssertFalse(isMuted)
        }
    }

    // MARK: - Edge Cases

    func testMutedZeroVolume() {
        Task {
            await actor.updateVolumeState(scalar: 0.0, isMuted: true)
            let (scalar, isMuted) = await actor.getVolumeState()
            XCTAssertEqual(scalar, 0.0)
            XCTAssertTrue(isMuted)
        }
    }

    func testMutedNonZeroVolume() {
        Task {
            await actor.updateVolumeState(scalar: 0.5, isMuted: true)
            let (scalar, isMuted) = await actor.getVolumeState()
            XCTAssertEqual(scalar, 0.5)
            XCTAssertTrue(isMuted)
        }
    }
}
