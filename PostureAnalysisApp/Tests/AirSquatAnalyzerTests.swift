import XCTest
@testable import PostureAnalysisApp

final class AirSquatAnalyzerTests: XCTestCase {
    private let motion = AirSquatExercise.definition().guide.motion

    func testGuideDemonstrationCountsOncePerLoopAtAnyScaleAndProportions() {
        for (scale, thigh, shin) in [(CGFloat(1), CGFloat(1), CGFloat(1)), (0.5, 1, 1), (2, 1, 1),
                                     (1, 0.85, 1), (1, 1.15, 1), (1, 1, 0.85), (1, 1, 1.15)] {
            let result = run(motion, scale: scale, thigh: thigh, shin: shin)
            XCTAssertEqual(result.reps, 3, "scale \(scale), thigh \(thigh), shin \(shin)")
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "The demonstration raises no cues: \(result.forms)")
            XCTAssertTrue(result.signals.allSatisfy(\.isEmpty))
        }
    }

    func testShallowSquatDoesNotCountAndAsksToGoDeeper() {
        let result = run(variant([0.45]))
        XCTAssertEqual(result.reps, 0)
        XCTAssertEqual(result.forms.count, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags == [.squatDeeper] })
    }

    func testSquattingAgainWithoutStandingAsksToStandUp() {
        let result = run(variant([0.9, 0.4, 0.9]))
        XCTAssertEqual(result.reps, 3, "Only standing all the way up ends a rep.")
        XCTAssertEqual(result.forms.filter { $0.flags.contains(.squatStandUp) }.count, 3)
    }

    func testKneesCavingInAndLeaningForwardRaiseSignalsAtDepth() {
        let caving = run(motion, kneesIn: { $0 >= 4.5 ? 30 : 0 })
        XCTAssertFalse(caving.signals[..<45].contains { $0.contains(.squatKneesOut) })
        XCTAssertTrue(caving.signals[45...].contains { $0.contains(.squatKneesOut) })
        XCTAssertEqual(caving.reps, 3, "Form never affects counting.")

        let leaning = run(motion, lean: { $0 >= 4.5 ? 0.4 : 0 })
        XCTAssertTrue(leaning.signals[45...].contains { $0.contains(.squatChestUp) })
        XCTAssertFalse(run(motion, shoulders: false, lean: { $0 >= 4.5 ? 0.4 : 0 }).signals.contains { $0.contains(.squatChestUp) })
    }

    // MARK: - Helpers

    /// Stand, then each depth in turn (with 0.3 s holds), then stand.
    private func variant(_ depths: [Double]) -> ArmMotion {
        let arms = motion.startAngles
        var keyframes = [ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0)]
        for depth in depths {
            keyframes.append(ArmKeyframe(angles: arms, moveDuration: 1.0, holdDuration: 0.3, stepIndex: 1,
                                         legs: LegPose(hipDrop: depth, kneeSpread: 0.3)))
        }
        keyframes.append(ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0, stepIndex: 2))
        return ArmMotion(keyframes: keyframes, holdsDumbbells: false)
    }

    private struct Run {
        var reps = 0
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
    }

    /// Samples `motion` at 10 Hz for three loops on the demo figure, with optional scale and leg proportions,
    /// knees moving inward (pixels), and a forward lean (share of torso height lost at full depth).
    private func run(_ motion: ArmMotion, scale: CGFloat = 1, thigh: CGFloat = 1, shin: CGFloat = 1, shoulders: Bool = true,
                     kneesIn: (TimeInterval) -> CGFloat = { _ in 0 }, lean: (TimeInterval) -> CGFloat = { _ in 0 }) -> Run {
        var standing = ExerciseDemoFigureView.figureJoints
        for side in BodySide.allCases {
            guard let hip = standing[side.hip], let knee = standing[side.knee], let ankle = standing[side.ankle] else { continue }
            let newKnee = CGPoint(x: hip.x + (knee.x - hip.x) * thigh, y: hip.y + (knee.y - hip.y) * thigh)
            standing[side.knee] = newKnee
            standing[side.ankle] = CGPoint(x: newKnee.x + (ankle.x - knee.x) * shin, y: newKnee.y + (ankle.y - knee.y) * shin)
        }
        let analyzer = AirSquatAnalyzer(epoch: 1)
        var result = Run()
        for index in 0..<(Int(motion.duration * 10) * 3) {
            let time = Double(index) / 10
            let legs = motion.sample(at: time).legs
            var joints = ExerciseDemoFigureView.lowered(standing, by: legs)
            let depth = CGFloat(legs.hipDrop / 0.9)
            for side in BodySide.allCases {
                let outward: CGFloat = side == .left ? 1 : -1
                joints[side.knee]?.x -= outward * kneesIn(time) * depth
                joints[side.shoulder]?.y += lean(time) * 132 * depth
            }
            if !shoulders {
                joints[.leftShoulder] = nil
                joints[.rightShoulder] = nil
            }
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero,
                                imageLocation: CGPoint(x: point.x * scale + 300, y: point.y * scale + 200), confidence: 0.9))
            })
            let analysis = AirSquatAnalyzer.process(analyzer, PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time))
            result.reps += analysis.repEvents.count
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
        }
        return result
    }
}

private extension AirSquatAnalyzer {
    static func process(_ analyzer: AirSquatAnalyzer, _ frame: PoseFrame) -> ExerciseAnalysis {
        analyzer.process(frame, counting: true)
    }
}
