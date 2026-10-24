import XCTest
@testable import PostureAnalysisApp

/// Every catalog exercise shows its alignment ghost whenever the workout is ready, even with only the joints
/// framing requires in view (#68).
@MainActor
final class ReadyGhostInvariantTests: XCTestCase {
    /// Ready-state ghost gaps fixed by #69. Strict expected failures: fixing one without removing it here fails.
    private static let knownReadyGhostGaps: Set<ExerciseID> = [.airSquat, .dumbbellRow, .tricepsExtension]

    func testEveryCatalogExerciseShowsItsGhostWhenReady() {
        for exercise in ExerciseCatalog.all {
            let variants = ReadyPoseFixtures.variants(for: exercise)
            XCTAssertTrue(variants.contains { $0.name == "full" }, "\(exercise.id) has no full Ready pose")
            XCTAssertTrue(variants.contains { $0.isMinimal }, "\(exercise.id) has no minimal Ready pose")
            XCTAssertFalse(exercise.guide.motion.keyframes.isEmpty, "\(exercise.id) has no guide keyframes")

            for variant in variants {
                let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(),
                                                       initialExercise: exercise.id)
                harness.model.onAppear(isApplicationActive: true)
                harness.camera.emit(.running)
                var readyFrames = 0

                for _ in 0..<20 {
                    harness.camera.emit(.frame(ReadyPoseFixtures.frame(variant, at: harness.clock.now)))
                    if harness.model.session.phase == .ready {
                        readyFrames += 1
                        XCTAssertEqual(harness.model.hud.visual.overlay, .ghostDemo,
                                       "\(exercise.id) \(variant.name): Ready did not select the ghost overlay")
                        guard let overlay = harness.model.overlay else {
                            XCTFail("\(exercise.id) \(variant.name): Ready has no overlay")
                            harness.clock.advance(by: 0.1)
                            continue
                        }
                        let assertGhost = {
                            for (index, keyframe) in exercise.guide.motion.keyframes.enumerated() {
                                let geometry = WorkoutGhostGeometry.make(
                                    overlay: overlay,
                                    metrics: harness.model.guideMetrics,
                                    motion: exercise.guide.motion,
                                    cameraView: exercise.cameraView,
                                    containerSize: CGSize(width: 393, height: 852),
                                    angles: keyframe.angles,
                                    legs: keyframe.legs
                                )
                                XCTAssertFalse(geometry.isEmpty,
                                               "\(exercise.id) \(variant.name) keyframe \(index): ghost geometry is empty")
                            }
                        }

                        if variant.isMinimal && Self.knownReadyGhostGaps.contains(exercise.id) {
                            // Only the empty-geometry gap is expected; any other failure still fails the test.
                            let options = XCTExpectedFailure.Options()
                            options.issueMatcher = { $0.compactDescription.contains("ghost geometry is empty") }
                            XCTExpectFailure("Ready ghost gap, fixed by #69", options: options) {
                                assertGhost()
                            }
                        } else {
                            assertGhost()
                        }
                    }
                    harness.clock.advance(by: 0.1)
                }

                XCTAssertGreaterThan(readyFrames, 0, "\(exercise.id) \(variant.name) never reached Ready")
            }
        }
    }
}
