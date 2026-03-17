import XCTest
@testable import StreetStamps

final class MotionActivityFusionTests: XCTestCase {
    func test_trackingStationaryCandidate_rejectedWhenMotionSuggestsMovement() {
        let motion = MotionActivitySnapshot(kind: .walking, confidence: .high)

        let accepted = TrackingMotionFusion.shouldTreatAsStationary(
            gpsStationaryCandidate: true,
            motion: motion
        )

        XCTAssertFalse(accepted)
    }

    func test_trackingExitCandidate_acceptsMotionDrivenResume() {
        let motion = MotionActivitySnapshot(kind: .running, confidence: .high)

        let accepted = TrackingMotionFusion.shouldExitStationary(
            gpsExitCandidate: false,
            motion: motion
        )

        XCTAssertTrue(accepted)
    }

    func test_passiveMovingState_doesNotEnterStationaryWhenMotionSuggestsMovement() {
        let motion = MotionActivitySnapshot(kind: .walking, confidence: .medium)

        let accepted = PassiveMotionFusion.shouldEnterStationary(
            gpsStationaryCandidate: true,
            motion: motion
        )

        XCTAssertFalse(accepted)
    }

    func test_passiveStationaryState_acceptsMotionDrivenResume() {
        let motion = MotionActivitySnapshot(kind: .automotive, confidence: .high)

        let accepted = PassiveMotionFusion.shouldExitStationary(
            gpsExitCandidate: false,
            motion: motion
        )

        XCTAssertTrue(accepted)
    }

    func test_unknownMotionFallsBackToGpsOnlyBehavior() {
        let motion = MotionActivitySnapshot.unknown

        XCTAssertTrue(
            TrackingMotionFusion.shouldTreatAsStationary(
                gpsStationaryCandidate: true,
                motion: motion
            )
        )
        XCTAssertFalse(
            PassiveMotionFusion.shouldExitStationary(
                gpsExitCandidate: false,
                motion: motion
            )
        )
    }
}
