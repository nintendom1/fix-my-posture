import XCTest
@testable import PostureAnalysisApp

/// Every exercise, in every camera view, shows its ideal figure before tracking and fits that figure for every Ready
/// pose.
@MainActor
final class ReadyGhostInvariantTests: XCTestCase {
    private let containerSize = CGSize(width: 393, height: 852)

    func testEveryExerciseShowsItsGhostBeforeAnyoneIsInView() {
        let imageSize = WorkoutGhostGeometry.defaultImageSize
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        for exercise in ExerciseCatalog.everyView {
            let name = label(exercise)
            let harness = WorkoutCoachHarness.make(showing: exercise)
            harness.model.onAppear(isApplicationActive: true)
            harness.camera.emit(.running)

            XCTAssertEqual(harness.model.session.exercise?.cameraView, exercise.cameraView,
                           "\(name) did not open in its own camera view")
            XCTAssertEqual(harness.model.hud.visual.overlay, .ghostDemo,
                           "\(name) did not show the ideal ghost during framing")
            XCTAssertNil(harness.model.ghostFitOverlay, "\(name) calibrated before anyone was in view")
            XCTAssertFalse(exercise.guide.motion.keyframes.isEmpty, "\(name) has no guide keyframes")
            for (sampleLabel, sample) in motionSamples(exercise.guide.motion) {
                let figure = WorkoutGhostGeometry.ideal(overlay: nil, motion: exercise.guide.motion,
                                                        cameraView: exercise.cameraView,
                                                        containerSize: containerSize,
                                                        sample: sample)
                XCTAssertFalse(figure.isEmpty, "\(name) \(sampleLabel): ideal figure is empty")
                for (joint, point) in figure.joints {
                    XCTAssertTrue(fit.contains(point),
                                  "\(name) \(sampleLabel) \(joint) lies outside the default image fit")
                }
            }
        }
    }

    func testEveryReadyPoseCalibratesTheGhost() throws {
        for exercise in ExerciseCatalog.everyView {
            let name = label(exercise)
            let variants = ReadyPoseFixtures.variants(for: exercise)
            XCTAssertTrue(variants.contains { $0.name == "full" }, "\(name) has no full Ready pose")
            XCTAssertTrue(variants.contains { $0.isMinimal }, "\(name) has no minimal Ready pose")
            XCTAssertFalse(exercise.guide.motion.keyframes.isEmpty, "\(name) has no guide keyframes")

            for variant in variants {
                let harness = WorkoutCoachHarness.make(showing: exercise)
                harness.model.onAppear(isApplicationActive: true)
                harness.camera.emit(.running)
                var readyFrames = 0

                for _ in 0..<20 {
                    harness.camera.emit(.frame(ReadyPoseFixtures.frame(variant, at: harness.clock.now)))
                    if harness.model.session.phase == .ready {
                        readyFrames += 1
                        XCTAssertEqual(harness.model.session.exercise?.cameraView, exercise.cameraView,
                                       "\(name) \(variant.name): Ready is in another camera view")
                        XCTAssertEqual(harness.model.hud.visual.overlay, .ghostDemo,
                                       "\(name) \(variant.name): Ready did not select the ghost overlay")
                        let fitOverlay = try XCTUnwrap(harness.model.ghostFitOverlay,
                                                       "\(name) \(variant.name): Ready has no calibrated overlay")
                        let overlay = try XCTUnwrap(harness.model.overlay,
                                                    "\(name) \(variant.name): Ready has no live overlay")
                        for (sampleLabel, sample) in motionSamples(exercise.guide.motion) {
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
                                           "\(name) \(variant.name) \(sampleLabel): canFit disagreed with calibration")
                            XCTAssertFalse(try XCTUnwrap(figure,
                                                         "\(name) \(variant.name) \(sampleLabel): calibration failed").isEmpty,
                                           "\(name) \(variant.name) \(sampleLabel): calibrated figure is empty")
                        }
                        XCTAssertNotNil(overlay)
                    }
                    harness.clock.advance(by: 0.1)
                }

                XCTAssertGreaterThan(readyFrames, 0, "\(name) \(variant.name) never reached Ready")
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

    /// "hammer_curl (side)", so a failure names the view.
    private func label(_ exercise: ExerciseDefinition) -> String {
        "\(exercise.id.rawValue) (\(exercise.cameraView.rawValue))"
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
