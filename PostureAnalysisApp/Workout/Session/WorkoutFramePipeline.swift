import CoreGraphics
import Foundation

/// Owns the deterministic work performed for each pose sample. It has no camera, clock, or UI
/// dependencies; the caller sends the reducer events in order and applies their effects.
struct WorkoutFramePipeline {
    struct FrameOutput {
        let events: [WorkoutEvent]
        let overlay: WorkoutOverlayState?
        let ghostFitOverlay: WorkoutOverlayState?
        let guideMetrics: GuideMetrics?
        let readings: [BodySide: ArmReading]
        let thresholds: [BodySide: ArmThresholds]
        let formReadings: [FormReading]
    }

    private(set) var exercise: ExerciseDefinition?
    private(set) var analyzerEpoch: Int
    private(set) var isCounting: Bool
    private(set) var overlay: WorkoutOverlayState?
    private(set) var ghostFitOverlay: WorkoutOverlayState?
    private(set) var guideMetrics: GuideMetrics?
    private(set) var readings: [BodySide: ArmReading] = [:]
    private(set) var thresholds: [BodySide: ArmThresholds] = [:]
    private(set) var formReadings: [FormReading] = []

    private var analyzer: ExerciseAnalyzing?
    private var framingEvaluator: FramingEvaluator?
    private var offscreenJointEstimator: OffscreenJointEstimator?
    private var ghostCalibrationGate = GhostCalibrationGate()
    private var lastFramingStatus: FramingStatus?
    private var smoother = LandmarkSmoother()
    private var lastStartPositionHeld = false
    private var emphasizedJoints: Set<LandmarkType> = []
    private var sessionPhase: WorkoutPhase = .framing
    private var tiltDetector = PhoneTiltDetector()
    private var lastReportedTilt = false

    init(exercise: ExerciseDefinition? = nil, analyzerEpoch: Int = 0, isCounting: Bool = false) {
        self.exercise = nil
        self.analyzerEpoch = analyzerEpoch
        self.isCounting = isCounting
        if let exercise {
            exerciseChanged(to: exercise, analyzerEpoch: analyzerEpoch)
        }
    }

    mutating func process(frame: PoseFrame, at now: TimeInterval) -> FrameOutput {
        guard let exercise else {
            overlay = nil
            ghostCalibrationGate.reset()
            ghostFitOverlay = nil
            return output(events: [])
        }

        var completed = frame
        if var estimator = offscreenJointEstimator {
            completed = estimator.complete(frame)
            offscreenJointEstimator = estimator
        }
        let counted = sessionPhase == .exercising ? completed : frame

        var events: [WorkoutEvent] = []
        if var evaluator = framingEvaluator {
            let status = evaluator.evaluate(counted)
            framingEvaluator = evaluator
            if status != lastFramingStatus {
                let previous = lastFramingStatus
                lastFramingStatus = status
                events.append(.framingChanged(status))
                // During a set, framing reliability controls analyzer counting on this same frame.
                // The reducer will emit the matching `.setCounting` effect when it handles the event.
                if sessionPhase == .exercising,
                   status.isReliable != (previous?.isReliable ?? false) {
                    isCounting = status.isReliable
                }
            }
        }

        updateGuideMetrics(frame, for: exercise)

        var endSides: Set<BodySide> = []
        if let analyzer {
            let analysis = analyzer.process(counted, counting: isCounting)
            if isCounting { endSides = analysis.endPositionSides }
            readings = analysis.readings
            thresholds = analysis.thresholds
            if analysis.startPositionHeld != lastStartPositionHeld {
                lastStartPositionHeld = analysis.startPositionHeld
                events.append(.startPositionChanged(analysis.startPositionHeld))
            }
            events.append(contentsOf: analysis.repEvents.map(WorkoutEvent.repCompleted))
            formReadings = analysis.formReadings
            // Keep the current ordering: reps are handled before form observations, so a cue from
            // the old set cannot arrive after a rep completed it.
            if isCounting {
                events.append(.formObserved(FormObservation(epoch: analyzer.epoch,
                                                            repForms: analysis.repForms,
                                                            signals: analysis.formSignals)))
            }
        }

        if frame.pose.landmarks.isEmpty {
            overlay = nil
        } else {
            let display = Self.displayPose(frame.pose)
            overlay = WorkoutOverlayState(
                imageSize: frame.imageSize,
                joints: smoother.update(pose: display, joints: exercise.focusJoints, at: frame.timestamp),
                segments: exercise.focusSegments,
                endPositionSides: endSides,
                pose: display,
                emphasizedJoints: emphasizedJoints
            )
        }

        let available = GhostCalibration.canFit(overlay: overlay, metrics: guideMetrics,
                                                motion: exercise.guide.motion, cameraView: exercise.cameraView,
                                                sample: exercise.guide.motion.startSample)
        let calibrated = ghostCalibrationGate.update(available: available, at: frame.timestamp)
        if calibrated && available {
            ghostFitOverlay = overlay
        } else if !calibrated {
            ghostFitOverlay = nil
        }
        return output(events: events)
    }

    /// Rebuilds framing and counting state when a new exercise or camera view is selected.
    mutating func exerciseChanged(to exercise: ExerciseDefinition?, analyzerEpoch: Int) {
        let trackingChanged = self.exercise?.id != exercise?.id
            || self.exercise?.cameraView != exercise?.cameraView
        self.exercise = exercise

        if trackingChanged {
            framingEvaluator = exercise.map(Self.makeFramingEvaluator)
            offscreenJointEstimator = exercise.map {
                OffscreenJointEstimator(joints: $0.focusJoints, plantedJoints: $0.plantedJoints)
            }
            lastFramingStatus = nil
            smoother.reset()
            readings = [:]
            thresholds = [:]
            formReadings = []
            overlay = nil
            ghostCalibrationGate.reset()
            ghostFitOverlay = nil
            lastStartPositionHeld = false
            rebuildAnalyzer(epoch: analyzerEpoch)
        } else if self.analyzerEpoch != analyzerEpoch || (exercise != nil && analyzer == nil) {
            rebuildAnalyzer(epoch: analyzerEpoch)
        }
    }

    /// A camera-view change also starts a fresh analyzer, even when the exercise id is unchanged.
    mutating func viewChanged(to cameraView: ExerciseCameraView, analyzerEpoch: Int) {
        guard var exercise, exercise.cameraView != cameraView else {
            if self.analyzerEpoch != analyzerEpoch { rebuildAnalyzer(epoch: analyzerEpoch) }
            return
        }
        exercise.cameraView = cameraView
        exerciseChanged(to: exercise, analyzerEpoch: analyzerEpoch)
    }

    mutating func resetAnalyzer(epoch: Int) {
        guard analyzerEpoch != epoch || (exercise != nil && analyzer == nil) else { return }
        rebuildAnalyzer(epoch: epoch)
    }

    mutating func setCounting(_ counting: Bool) {
        isCounting = counting
    }

    mutating func setSessionPhase(_ phase: WorkoutPhase) {
        sessionPhase = phase
    }

    mutating func setEmphasizedJoints(_ joints: Set<LandmarkType>) {
        emphasizedJoints = joints
        overlay?.emphasizedJoints = joints
    }

    /// Returns a reducer event only when the debounced tilt state changes.
    mutating func processTiltSample(pitchDegrees: Double?, at now: TimeInterval) -> WorkoutEvent? {
        if !(exercise?.warnsAboutTilt ?? true) {
            tiltDetector.reset()
        } else {
            _ = tiltDetector.update(pitchDegrees: pitchDegrees, at: now)
        }
        let tilted = tiltDetector.isTilted
        guard tilted != lastReportedTilt else { return nil }
        lastReportedTilt = tilted
        return .phoneTiltChanged(tilted)
    }

    mutating func resetTilt() -> WorkoutEvent? {
        tiltDetector.reset()
        guard lastReportedTilt else { return nil }
        lastReportedTilt = false
        return .phoneTiltChanged(false)
    }

    /// Clears per-capture smoothing and framing state without replacing the exercise analyzer.
    mutating func resetTracking() -> [WorkoutEvent] {
        framingEvaluator?.reset()
        offscreenJointEstimator?.reset()
        lastFramingStatus = nil
        smoother.reset()
        overlay = nil
        ghostCalibrationGate.reset()
        ghostFitOverlay = nil
        guideMetrics = nil
        readings = [:]
        thresholds = [:]
        formReadings = []
        var events: [WorkoutEvent] = []
        if lastStartPositionHeld {
            lastStartPositionHeld = false
            events.append(.startPositionChanged(false))
        }
        return events
    }

    private mutating func rebuildAnalyzer(epoch: Int) {
        analyzerEpoch = epoch
        analyzer = exercise?.makeAnalyzer(epoch)
    }

    private static func makeFramingEvaluator(for exercise: ExerciseDefinition) -> FramingEvaluator {
        FramingEvaluator(requiredJoints: exercise.requiredJoints,
                         anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                         headroomArmLengths: exercise.headroomArmLengths,
                         sideroomArmLengths: exercise.sideroomArmLengths,
                         cameraView: exercise.cameraView)
    }

    private mutating func updateGuideMetrics(_ frame: PoseFrame, for exercise: ExerciseDefinition) {
        let confidence = FramingConfiguration().minimumConfidence
        guard let reference = metricsReference(frame, confidence: confidence,
                                              cameraView: exercise.cameraView,
                                              motion: exercise.guide.motion) else { return }
        let arms = BodySide.allCases.compactMap { ArmGeometry.arm($0, in: frame, minimumConfidence: confidence) }
        func measured(_ lengths: [CGFloat], typical: CGFloat) -> CGFloat {
            let plausible = lengths.filter { reference.plausible.contains($0 / reference.length) }
            guard !plausible.isEmpty else { return reference.length * typical }
            return plausible.reduce(0, +) / CGFloat(plausible.count)
        }
        let sample = GuideMetrics(upperArm: measured(arms.map(\.upperArmLength), typical: reference.upperArm),
                                  forearm: measured(arms.map(\.forearmLength), typical: reference.forearm))
        guard let previous = guideMetrics else {
            guideMetrics = sample
            return
        }
        let k = GuideMetrics.smoothing
        guideMetrics = GuideMetrics(upperArm: previous.upperArm + (sample.upperArm - previous.upperArm) * k,
                                    forearm: previous.forearm + (sample.forearm - previous.forearm) * k)
    }

    /// Shoulder width is the frontal reference. Side-body motions use Ready's leg joints; other side views keep
    /// preferring torso length and fall back to a visible upper arm.
    func metricsReference(_ frame: PoseFrame, confidence: Double, cameraView: ExerciseCameraView,
                          motion: ArmMotion)
        -> (length: CGFloat, upperArm: CGFloat, forearm: CGFloat, plausible: ClosedRange<CGFloat>)? {
        if cameraView == .side {
            if motion.movesSideBody {
                let figureHip = ExerciseDemoFigureView.sideFigureJoints[.leftHip] ?? .zero
                let figureKnee = ExerciseDemoFigureView.sideFigureJoints[.leftKnee] ?? .zero
                let figureAnkle = ExerciseDemoFigureView.sideFigureJoints[.leftAnkle] ?? .zero
                let figureLeg = ArmGeometry.distance(figureHip, figureKnee)
                    + ArmGeometry.distance(figureKnee, figureAnkle)
                guard figureLeg > 1 else { return nil }
                for side in BodySide.allCases {
                    guard let shoulder = frame.point(side.shoulder, minimumConfidence: confidence),
                          let hip = frame.point(side.hip, minimumConfidence: confidence),
                          let knee = frame.point(side.knee, minimumConfidence: confidence),
                          let ankle = frame.point(side.ankle, minimumConfidence: confidence) else { continue }
                    let legLength = ArmGeometry.distance(hip, knee) + ArmGeometry.distance(knee, ankle)
                    guard legLength > 1, ArmGeometry.distance(shoulder, hip) > 1 else { continue }
                    return (legLength,
                            ExerciseDemoFigureView.upperArm / figureLeg,
                            ExerciseDemoFigureView.forearm / figureLeg,
                            0.2...0.65)
                }
                return nil
            }
            for side in BodySide.allCases {
                guard let shoulder = frame.point(side.shoulder, minimumConfidence: confidence),
                      let hip = frame.point(side.hip, minimumConfidence: confidence) else { continue }
                let torso = ArmGeometry.distance(shoulder, hip)
                if torso > 1 {
                    return (torso, GuideMetrics.upperArmToTorso, GuideMetrics.forearmToTorso,
                            GuideMetrics.plausibleTorsoRatio)
                }
            }
            let upperArms = BodySide.allCases.compactMap { side -> CGFloat? in
                guard let shoulder = frame.point(side.shoulder, minimumConfidence: confidence),
                      let elbow = frame.point(side.elbow, minimumConfidence: confidence) else { return nil }
                let length = ArmGeometry.distance(shoulder, elbow)
                return length > 1 ? length : nil
            }
            guard let upperArm = upperArms.max() else { return nil }
            return (upperArm, 1, GuideMetrics.forearmToUpperArm, GuideMetrics.plausibleUpperArmRatio)
        }
        guard let left = frame.point(.leftShoulder, minimumConfidence: confidence),
              let right = frame.point(.rightShoulder, minimumConfidence: confidence) else { return nil }
        let width = ArmGeometry.distance(left, right)
        guard width > 1 else { return nil }
        return (width, GuideMetrics.upperArmToShoulderWidth, GuideMetrics.forearmToShoulderWidth,
                GuideMetrics.plausibleSegmentRatio)
    }

    private static func displayPose(_ pose: BodyPose) -> BodyPose {
        var display = pose
        display.landmarks = pose.landmarks.mapValues { landmark in
            var mirrored = landmark
            mirrored.normalizedLocation.x = 1 - landmark.normalizedLocation.x
            mirrored.imageLocation = CoordinateConverter.normalizedToImagePixel(
                normalized: mirrored.normalizedLocation,
                imageWidth: pose.imageWidth,
                imageHeight: pose.imageHeight
            )
            return mirrored
        }
        return display
    }

    private func output(events: [WorkoutEvent]) -> FrameOutput {
        FrameOutput(events: events, overlay: overlay, ghostFitOverlay: ghostFitOverlay, guideMetrics: guideMetrics,
                    readings: readings, thresholds: thresholds, formReadings: formReadings)
    }
}
