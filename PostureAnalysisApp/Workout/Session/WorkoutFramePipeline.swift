import CoreGraphics
import Foundation

/// Owns the deterministic work performed for each pose sample. It has no camera, clock, or UI
/// dependencies; the caller sends the reducer events in order and applies their effects.
struct WorkoutFramePipeline {
    private struct BufferedViewChangeFrame {
        let frame: PoseFrame
        var sessionPhase: WorkoutPhase
        var isCounting: Bool
    }

    struct FrameOutput {
        let events: [WorkoutEvent]
        let overlay: WorkoutOverlayState?
        let ghostFitOverlay: WorkoutOverlayState?
        let guideMetrics: GuideMetrics?
        let readings: [BodySide: ArmReading]
        let thresholds: [BodySide: ArmThresholds]
        let formReadings: [FormReading]
        /// Everything this frame decided, for a session recording; nil unless `collectsDiagnostics` is on.
        let diagnostics: FrameDiagnostics?
    }

    /// One frame's inputs and decisions, beyond what the overlay and HUD need.
    struct FrameDiagnostics {
        /// The frame framing and the analyzer saw: during a set it carries joints estimated past the frame edge.
        let analyzedFrame: PoseFrame
        /// This frame's framing result; `events` reports it only when it changes.
        let framing: FramingStatus?
        /// The counting flag passed to the analyzer.
        let counting: Bool
        let analysis: ExerciseAnalysis?
        /// The frame's stance classification when the detector is connected.
        var stance: StanceDetector.Reading? = nil
    }

    /// A change the coach makes between frames. The coach and session replay both go through `apply`,
    /// so a recording's controls rebuild exactly the pipeline state the coach had.
    enum Control {
        case sessionPhase(WorkoutPhase)
        case exercise(ExerciseDefinition?, analyzerEpoch: Int)
        case resetAnalyzer(epoch: Int)
        case counting(Bool)
        case resetTracking
    }

    /// The state controls change. A control that leaves it unchanged was a no-op, so a recording can skip it.
    struct ControlState: Equatable {
        var exerciseID: ExerciseID?
        var cameraView: ExerciseCameraView?
        var analyzerEpoch: Int
        var hasAnalyzer: Bool
        var isCounting: Bool
        var sessionPhase: WorkoutPhase
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
    /// Attaches `FrameDiagnostics` to every output, for a session recording.
    var collectsDiagnostics = false
    /// Detects stance and bridges turns with every view's framing, for an exercise with a view choice. Strict replay
    /// turns it off for a recording made before camera views, which ran without either.
    var detectsStance = true

    private var analyzer: ExerciseAnalyzing?
    private var framingEvaluator: FramingEvaluator?
    /// Every camera view's framing requirement for an exercise with a view choice; empty otherwise.
    private var viewRequirements: [FramingRequirement] = []
    /// Raw frames that can seed the next camera view after stance settles or a view is locked.
    private var viewChangeFrames: [BufferedViewChangeFrame] = []
    /// When the count last rose; a view warm-up doesn't count before it, so the new view can't credit it again.
    private var lastRepCreditTime: TimeInterval?
    /// Each side's rep credits in this set. Like the session, a two-sided exercise counts the lower side.
    private var creditedSideReps: [BodySide: Int] = [:]
    private var offscreenJointEstimator: OffscreenJointEstimator?
    private var stanceDetector = StanceDetector()
    private var ghostCalibrationGate = GhostCalibrationGate()
    private var lastFramingStatus: FramingStatus?
    private var smoother = LandmarkSmoother()
    private var lastStartPositionHeld = false
    private var shouldReportStartPositionRelease = false
    private var shouldPrimeFraming = false
    private var emphasizedJoints: Set<LandmarkType> = []
    private(set) var sessionPhase: WorkoutPhase = .framing
    private var tiltDetector = PhoneTiltDetector()
    private var lastReportedTilt = false

    /// Framing and off-edge estimation settings; replay passes the ones a recording was made with.
    let framingConfiguration: FramingConfiguration
    let offscreenConfiguration: OffscreenJointConfiguration

    init(exercise: ExerciseDefinition? = nil, analyzerEpoch: Int = 0, isCounting: Bool = false,
         framingConfiguration: FramingConfiguration = FramingConfiguration(),
         offscreenConfiguration: OffscreenJointConfiguration = OffscreenJointConfiguration()) {
        self.framingConfiguration = framingConfiguration
        self.offscreenConfiguration = offscreenConfiguration
        self.exercise = nil
        self.analyzerEpoch = analyzerEpoch
        self.isCounting = isCounting
        if let exercise {
            exerciseChanged(to: exercise, analyzerEpoch: analyzerEpoch)
        }
    }

    var controlState: ControlState {
        ControlState(exerciseID: exercise?.id, cameraView: exercise?.cameraView, analyzerEpoch: analyzerEpoch,
                     hasAnalyzer: analyzer != nil, isCounting: isCounting, sessionPhase: sessionPhase)
    }

    var bufferedViewChangeFrameCount: Int { viewChangeFrames.count }

    /// Applies one control and returns any events it produced.
    mutating func apply(_ control: Control) -> [WorkoutEvent] {
        switch control {
        case .sessionPhase(let phase):
            setSessionPhase(phase)
        case .exercise(let exercise, let epoch):
            exerciseChanged(to: exercise, analyzerEpoch: epoch)
        case .resetAnalyzer(let epoch):
            resetAnalyzer(epoch: epoch)
        case .counting(let counting):
            setCounting(counting)
        case .resetTracking:
            return resetTracking()
        }
        return []
    }

    mutating func process(frame: PoseFrame, at now: TimeInterval) -> FrameOutput {
        guard let exercise else {
            viewChangeFrames.removeAll()
            lastRepCreditTime = nil
            overlay = nil
            ghostCalibrationGate.reset()
            ghostFitOverlay = nil
            return output(events: [], diagnostics: collectsDiagnostics
                ? FrameDiagnostics(analyzedFrame: frame, framing: nil, counting: isCounting, analysis: nil) : nil)
        }

        bufferForViewChange(frame, exercise: exercise)
        let completed = completeOffscreenJoints(in: frame)
        let counted = sessionPhase == .exercising ? completed : frame

        var events: [WorkoutEvent] = []
        var stanceReading: StanceDetector.Reading?
        var stanceObservationChange: StanceDetector.Observation?
        let tracksStance = detectsStance && exercise.hasViewChoice
        if tracksStance {
            stanceReading = StanceDetector.reading(of: frame, configuration: .standard)
            let previousObservation = stanceDetector.observation
            let observation = stanceDetector.update(frame)
            if observation != previousObservation {
                stanceObservationChange = observation
            }
        }

        var framing: FramingStatus?
        if var evaluator = framingEvaluator {
            // Partway through a turn, neither view may see the whole body yet. From the first reading that suggests a
            // turn, a frame that any of the exercise's views could track keeps framing, so counting carries on until
            // the new view takes over. The detector bounds the whole turn, so evidence that flickers can't extend it.
            let alternatives = tracksStance && stanceDetector.mayBeTurning ? viewRequirements : []
            if shouldPrimeFraming {
                evaluator.prime(with: counted, alsoAccepting: alternatives)
                shouldPrimeFraming = false
            }
            let status = evaluator.evaluate(counted, alsoAccepting: alternatives)
            framingEvaluator = evaluator
            framing = status
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

        if shouldReportStartPositionRelease {
            events.append(.startPositionChanged(false))
            shouldReportStartPositionRelease = false
        }

        updateGuideMetrics(frame, for: exercise)

        var endSides: Set<BodySide> = []
        var analyzed: ExerciseAnalysis?
        let analyzedCounting = isCounting
        recordFrameContext(frame, counting: analyzedCounting)
        if let analysis = feedAnalyzer(counted, counting: isCounting) {
            analyzed = analysis
            if isCounting { endSides = analysis.endPositionSides }
            readings = analysis.readings
            thresholds = analysis.thresholds
            if analysis.startPositionHeld != lastStartPositionHeld {
                lastStartPositionHeld = analysis.startPositionHeld
                events.append(.startPositionChanged(analysis.startPositionHeld))
            }
            events.append(contentsOf: analysis.repEvents.map(WorkoutEvent.repCompleted))
            if recordRepCredits(analysis.repEvents, exercise: exercise) { lastRepCreditTime = frame.timestamp }
            formReadings = analysis.formReadings
            // Keep the current ordering: reps are handled before form observations, so a cue from
            // the old set cannot arrive after a rep completed it.
            if isCounting {
                events.append(.formObserved(FormObservation(epoch: analyzerEpoch,
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
                joints: updateSmoother(for: display, joints: exercise.focusJoints, at: frame.timestamp),
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
        if let stanceObservationChange {
            events.append(.stanceObserved(stanceObservationChange))
        }
        return output(events: events, diagnostics: collectsDiagnostics
            ? FrameDiagnostics(analyzedFrame: counted, framing: framing, counting: analyzedCounting,
                               analysis: analyzed, stance: stanceReading)
            : nil)
    }

    /// Rebuilds framing and counting state when a new exercise or camera view is selected.
    mutating func exerciseChanged(to exercise: ExerciseDefinition?, analyzerEpoch: Int) {
        let idChanged = self.exercise?.id != exercise?.id
        let viewChanged = !idChanged && self.exercise?.cameraView != exercise?.cameraView
        let trackingChanged = idChanged || viewChanged
        self.exercise = exercise

        if trackingChanged {
            var loneCredits: Set<BodySide> = []
            if idChanged {
                viewChangeFrames.removeAll()
                lastRepCreditTime = nil
                creditedSideReps = [:]
            } else if exercise?.perSide == false {
                // The session evens the sides at a view change, dropping a one-sided credit.
                let counted = countedReps
                loneCredits = Set(BodySide.allCases.filter { (creditedSideReps[$0] ?? 0) > counted })
                creditedSideReps = [.left: counted, .right: counted]
            }
            let previousFraming = framingEvaluator
            framingEvaluator = exercise.map(makeFramingEvaluator)
            // The user is still in view after a camera-view change, so framing keeps its reliability and grace.
            if viewChanged, let previousFraming {
                framingEvaluator?.continueReliability(from: previousFraming)
            }
            viewRequirements = exercise.map { exercise in
                guard exercise.hasViewChoice else { return [] }
                return exercise.everyView.map {
                    FramingRequirement(requiredJoints: $0.requiredJoints, anyOfRequiredJoints: $0.anyOfRequiredJoints)
                }
            } ?? []
            offscreenJointEstimator = exercise.map {
                OffscreenJointEstimator(joints: $0.focusJoints, plantedJoints: $0.plantedJoints,
                                        configuration: offscreenConfiguration)
            }
            smoother.reset()
            readings = [:]
            thresholds = [:]
            formReadings = []
            overlay = nil
            ghostCalibrationGate.reset()
            ghostFitOverlay = nil
            if idChanged {
                lastFramingStatus = nil
                lastStartPositionHeld = false
                shouldReportStartPositionRelease = false
                shouldPrimeFraming = false
                stanceDetector.reset(seed: exercise?.cameraView.stance)
            } else {
                guideMetrics = nil
                shouldReportStartPositionRelease = shouldReportStartPositionRelease || lastStartPositionHeld
                lastStartPositionHeld = false
                shouldPrimeFraming = exercise != nil
            }
            // A curl past its top in the old view counts when it's lowered in the new one. It resumes after the
            // warm-up, so it credits on a live frame once the new view confirms the start, at most once. The new
            // analyzer keeps its own attempt past the end, and one whose start it saw before that end.
            var carried = viewChanged && exercise?.hasViewChoice == true ? analyzer?.attemptInProgress() : nil
            carried?.pairCredits = loneCredits
            rebuildAnalyzer(epoch: analyzerEpoch)
            if viewChanged {
                warmAnalyzerFromViewChangeFrames()
                if let carried { analyzer?.resume(carried) }
            }
        } else if self.analyzerEpoch != analyzerEpoch || (exercise != nil && analyzer == nil) {
            creditedSideReps = [:]
            rebuildAnalyzer(epoch: analyzerEpoch)
        }
    }

    mutating func resetAnalyzer(epoch: Int) {
        guard analyzerEpoch != epoch || (exercise != nil && analyzer == nil) else { return }
        creditedSideReps = [:]
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

    /// Clears per-capture smoothing and framing state without replacing the exercise analyzer. Like the analyzer,
    /// framing keeps its supported-shoulder references; they expire on their own after a gap.
    mutating func resetTracking() -> [WorkoutEvent] {
        let previousStance = stanceDetector.observation
        viewChangeFrames.removeAll()
        lastRepCreditTime = nil
        stanceDetector.reset(seed: previousStance.settled)
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
        if stanceDetector.observation != previousStance {
            events.append(.stanceObserved(stanceDetector.observation))
        }
        return events
    }

    /// Framing's supported-shoulder references restart with the analyzer's, so counting and framing accept the same
    /// faint shoulders on every frame.
    private mutating func rebuildAnalyzer(epoch: Int) {
        analyzerEpoch = epoch
        analyzer = exercise?.makeAnalyzer(epoch)
        framingEvaluator?.resetSupportedShoulders()
    }

    private mutating func bufferForViewChange(_ frame: PoseFrame, exercise: ExerciseDefinition) {
        guard exercise.hasViewChoice else {
            viewChangeFrames.removeAll()
            return
        }

        viewChangeFrames.append(BufferedViewChangeFrame(frame: frame, sessionPhase: sessionPhase,
                                                        isCounting: isCounting))
        let horizon = StanceDetector.Configuration.standard.holdSeconds + Self.viewChangeFrameBufferMargin
        let cutoff = frame.timestamp - horizon
        viewChangeFrames.removeAll { $0.frame.timestamp < cutoff }
    }

    /// Replays only the settled-stance window. Historical outputs are discarded; only stage state survives.
    /// Frames up to the old view's last credited rep replay without counting: the views confirm the return to
    /// the start at different points, so the new view could otherwise credit that rep a second time. Those
    /// frames still teach the new view where the start is.
    private mutating func warmAnalyzerFromViewChangeFrames() {
        guard let exercise, exercise.hasViewChoice,
              let latestTime = viewChangeFrames.last?.frame.timestamp else { return }
        let cutoff = latestTime - StanceDetector.Configuration.standard.holdSeconds
            - StanceDetector.timeTolerance
        let framesToReplay = viewChangeFrames.filter { $0.frame.timestamp >= cutoff }
        for buffered in framesToReplay {
            let frame = buffered.frame
            let completed = completeOffscreenJoints(in: frame)
            let counted = buffered.sessionPhase == .exercising ? completed : frame
            let afterLastCredit = lastRepCreditTime.map { frame.timestamp > $0 } ?? true
            _ = feedAnalyzer(counted, counting: buffered.isCounting && afterLastCredit)
            if !frame.pose.landmarks.isEmpty {
                let display = Self.displayPose(frame.pose)
                _ = updateSmoother(for: display, joints: exercise.focusJoints, at: frame.timestamp)
            }
        }
    }

    /// Records the analyzer's rep credits and whether the count rose with them. One arm's credit alone doesn't
    /// raise a two-sided exercise's count, and the other arm's attempt may still finish after a view change.
    private mutating func recordRepCredits(_ events: [RepEvent], exercise: ExerciseDefinition) -> Bool {
        guard !events.isEmpty else { return false }
        if exercise.perSide { return true }
        let before = countedReps
        for event in events {
            for side in event.sides { creditedSideReps[side, default: 0] += 1 }
        }
        return countedReps > before
    }

    private var countedReps: Int { min(creditedSideReps[.left] ?? 0, creditedSideReps[.right] ?? 0) }

    private mutating func recordFrameContext(_ frame: PoseFrame, counting: Bool) {
        guard let lastIndex = viewChangeFrames.indices.last,
              viewChangeFrames[lastIndex].frame.timestamp == frame.timestamp else { return }
        viewChangeFrames[lastIndex].sessionPhase = sessionPhase
        viewChangeFrames[lastIndex].isCounting = counting
    }

    private mutating func completeOffscreenJoints(in frame: PoseFrame) -> PoseFrame {
        guard var estimator = offscreenJointEstimator else { return frame }
        let completed = estimator.complete(frame)
        offscreenJointEstimator = estimator
        return completed
    }

    /// The same analyzer feed is used for live frames and silent view warm-up.
    private func feedAnalyzer(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis? {
        analyzer?.process(frame, counting: counting)
    }

    private mutating func updateSmoother(for pose: BodyPose, joints: Set<LandmarkType>,
                                         at time: TimeInterval) -> [LandmarkType: OverlayJoint] {
        smoother.update(pose: pose, joints: joints, at: time)
    }

    private func makeFramingEvaluator(for exercise: ExerciseDefinition) -> FramingEvaluator {
        var configuration = framingConfiguration
        if let grace = exercise.framingUnreliableAfter {
            configuration.unreliableAfter = max(configuration.unreliableAfter, grace)
        }
        return FramingEvaluator(requiredJoints: exercise.requiredJoints,
                                anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                                headroomArmLengths: exercise.headroomArmLengths,
                                sideroomArmLengths: exercise.sideroomArmLengths,
                                maximumShoulderSpan: exercise.maximumShoulderSpan,
                                maximumWristHeightFraction: exercise.maximumWristHeightFraction,
                                supportedShoulders: exercise.supportedShoulders,
                                centersInFrame: exercise.centersInFrame,
                                cameraView: exercise.cameraView, configuration: configuration)
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

    private static let viewChangeFrameBufferMargin: TimeInterval = 0.25

    /// Shoulder width is the frontal reference. Side-body motions use Ready's leg joints; other side views keep
    /// preferring torso length and fall back to a visible upper arm.
    func metricsReference(_ frame: PoseFrame, confidence: Double, cameraView: ExerciseCameraView,
                          motion: ArmMotion)
        -> (length: CGFloat, upperArm: CGFloat, forearm: CGFloat, plausible: ClosedRange<CGFloat>)? {
        if cameraView == .side || cameraView == .lyingSide {
            if motion.movesSideBody {
                let figureLeg: CGFloat
                if cameraView == .lyingSide {
                    figureLeg = ExerciseDemoFigureView.lyingSideThigh + ExerciseDemoFigureView.lyingSideShin
                } else {
                    let figureHip = ExerciseDemoFigureView.sideFigureJoints[.leftHip] ?? .zero
                    let figureKnee = ExerciseDemoFigureView.sideFigureJoints[.leftKnee] ?? .zero
                    let figureAnkle = ExerciseDemoFigureView.sideFigureJoints[.leftAnkle] ?? .zero
                    figureLeg = ArmGeometry.distance(figureHip, figureKnee)
                        + ArmGeometry.distance(figureKnee, figureAnkle)
                }
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

    private func output(events: [WorkoutEvent], diagnostics: FrameDiagnostics?) -> FrameOutput {
        FrameOutput(events: events, overlay: overlay, ghostFitOverlay: ghostFitOverlay, guideMetrics: guideMetrics,
                    readings: readings, thresholds: thresholds, formReadings: formReadings, diagnostics: diagnostics)
    }
}
