import XCTest
@testable import PostureAnalysisApp

/// Every exercise shows its ideal figure before tracking and fits that figure for every Ready pose.
@MainActor
final class ReadyGhostInvariantTests: XCTestCase {
    private let containerSize = CGSize(width: 393, height: 852)

    func testEveryExerciseShowsItsGhostBeforeAnyoneIsInView() {
        let imageSize = WorkoutGhostGeometry.defaultImageSize
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        for exercise in ExerciseCatalog.all {
            let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(),
                                                   initialExercise: exercise.id)
            harness.model.onAppear(isApplicationActive: true)
            harness.camera.emit(.running)

            XCTAssertEqual(harness.model.hud.visual.overlay, .ghostDemo,
                           "\(exercise.id) did not show the ideal ghost during framing")
            XCTAssertNil(harness.model.ghostFitOverlay, "\(exercise.id) calibrated before anyone was in view")
            XCTAssertFalse(exercise.guide.motion.keyframes.isEmpty, "\(exercise.id) has no guide keyframes")
            for (label, sample) in motionSamples(exercise.guide.motion) {
                let figure = WorkoutGhostGeometry.ideal(overlay: nil, motion: exercise.guide.motion,
                                                        cameraView: exercise.cameraView,
                                                        containerSize: containerSize,
                                                        sample: sample)
                XCTAssertFalse(figure.isEmpty, "\(exercise.id) \(label): ideal figure is empty")
                for (joint, point) in figure.joints {
                    XCTAssertTrue(fit.contains(point),
                                  "\(exercise.id) \(label) \(joint) lies outside the default image fit")
                }
            }
        }
    }

    func testEveryReadyPoseCalibratesTheGhost() throws {
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
                        let fitOverlay = try XCTUnwrap(harness.model.ghostFitOverlay,
                                                       "\(exercise.id) \(variant.name): Ready has no calibrated overlay")
                        let overlay = try XCTUnwrap(harness.model.overlay,
                                                    "\(exercise.id) \(variant.name): Ready has no live overlay")
                        for (label, sample) in motionSamples(exercise.guide.motion) {
                            let canFit = GhostCalibration.canFit(overlay: fitOverlay,
                                                                 metrics: harness.model.guideMetrics,
                                                                 motion: exercise.guide.motion,
                                                                 cameraView: exercise.cameraView,
                                                                 sample: sample)
                            let figure = WorkoutGhostGeometry.calibrated(
                                fitOverlay: fitOverlay,
                                metrics: harness.model.guideMetrics,
                                motion: exercise.guide.motion,
                                cameraView: exercise.cameraView,
                                containerSize: containerSize,
                                sample: sample
                            )
                            XCTAssertEqual(canFit, figure != nil,
                                           "\(exercise.id) \(variant.name) \(label): canFit disagreed with calibration")
                            XCTAssertFalse(try XCTUnwrap(figure,
                                                         "\(exercise.id) \(variant.name) \(label): calibration failed").isEmpty,
                                           "\(exercise.id) \(variant.name) \(label): calibrated figure is empty")
                        }
                        XCTAssertNotNil(overlay)
                    }
                    harness.clock.advance(by: 0.1)
                }

                XCTAssertGreaterThan(readyFrames, 0, "\(exercise.id) \(variant.name) never reached Ready")
            }
        }
    }

    func testRestShowsTheGhost() throws {
        let exercise = ShoulderPressExercise.definition()
        let variant = try XCTUnwrap(ReadyPoseFixtures.variants(for: exercise).first { $0.name == "full" })
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), initialExercise: exercise.id)
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        for _ in 0..<20 {
            harness.camera.emit(.frame(ReadyPoseFixtures.frame(variant, at: harness.clock.now)))
            if harness.model.session.phase == .ready { break }
            harness.clock.advance(by: 0.1)
        }

        XCTAssertEqual(harness.model.session.phase, .ready)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        XCTAssertEqual(harness.model.session.phase, .resting)
        XCTAssertEqual(harness.model.hud.visual.overlay, .ghostDemo)
    }

    private func motionSamples(_ motion: ArmMotion) -> [(String, ArmMotionSample)] {
        var result: [(String, ArmMotionSample)] = []
        var elapsed: TimeInterval = 0
        for (index, keyframe) in motion.keyframes.enumerated() {
            result.append(("keyframe \(index)", motion.sample(of: keyframe)))
            if keyframe.moveDuration > 0 {
                for step in 1...4 {
                    result.append(("move \(index) sample \(step)",
                                   motion.sample(at: elapsed + keyframe.moveDuration * Double(step) / 5)))
                }
            }
            elapsed += keyframe.moveDuration + keyframe.holdDuration
        }
        return result
    }
}
