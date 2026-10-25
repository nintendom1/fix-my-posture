import CoreGraphics
import Foundation

/// Counts a side-view deadlift from standing torso pitch, through a hip hinge, and back to standing. The
/// angle is measured in pixel coordinates and needs only one complete side of the body.
final class StiffLegDeadliftAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: StiffLegDeadliftConfiguration
    private var nearSide = DeadliftNearSideSelector()
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var lockedReference: Reference?
    private var awayFromStartSince: TimeInterval?
    private var cycle: Cycle = .awaitingStart
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: StiffLegDeadliftFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedHinge: Bool)
    }

    /// The standing hip and torso ruler are locked through the hinge, so the guide lines do not move.
    private struct Reference {
        let hip: CGPoint
        let torsoLength: CGFloat
        let facing: CGFloat
    }

    init(epoch: Int, configuration: StiffLegDeadliftConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = StiffLegDeadliftFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        guard let selection = nearSide.select(in: frame, minimumConfidence: configuration.minimumJointConfidence,
                                              switchMargin: configuration.sideSwitchMargin) else {
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }
        let body = selection.body

        let time = frame.timestamp
        let hasGap = lastSample.map { time - $0 > configuration.maximumSampleGap } ?? false
        if selection.switched || hasGap { resetTracking() }
        lastSample = time

        let pitch = Self.torsoPitch(hip: body.hip, shoulder: body.shoulder)
        let zone = classify(pitch)
        let newlyConfirmed = tracker.update(zone)
        let liveReference = makeReference(for: body)
        updateReference(zone: zone, live: liveReference, at: time)
        let reference = lockedReference ?? liveReference

        lastThresholds = [body.side: makeThresholds(body: body, reference: reference)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? [body.side] : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let kneeAngle = ArmGeometry.angle(at: body.knee, body.hip, body.ankle)
        let formJoints: Set<LandmarkType> = [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee,
                                             .leftAnkle, .rightAnkle, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
        let hasEstimatedFormJoint = !frame.estimatedJoints.isDisjoint(with: formJoints)
        let form: StiffLegDeadliftFormMonitor.Output
        if hasEstimatedFormJoint {
            formMonitor.invalidate()
            form = StiffLegDeadliftFormMonitor.Output()
        } else {
            form = formMonitor.update(
                at: time,
                sample: .init(pitch: pitch, kneeAngle: kneeAngle, hip: body.hip, knee: body.knee,
                              ankle: body.ankle, wrist: body.wrist,
                              thighLength: ArmGeometry.distance(body.hip, body.knee)),
                zone: zone,
                confirmed: tracker.confirmed,
                counting: counting
            )
        }
        analysis.repForms = form.repForms
        analysis.formSignals = form.signals
        analysis.formReadings = formMonitor.readings

        guard counting else {
            cycle = .awaitingStart
            return analysis
        }
        switch cycle {
        case .awaitingStart:
            if tracker.confirmed == .bottom {
                cycle = .active(movementStart: time, reachedHinge: false)
            }
        case .active(var movementStart, var reachedHinge):
            if !reachedHinge, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedHinge = true }
            if newlyConfirmed == .bottom {
                if reachedHinge, time - movementStart >= configuration.minimumRepDuration {
                    // A whole-body rep counts for both sides, however many sides are tracked.
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                }
                movementStart = time
                reachedHinge = false
            }
            cycle = .active(movementStart: movementStart, reachedHinge: reachedHinge)
        }
        return analysis
    }

    private func classify(_ pitch: Double) -> MovementZone {
        if pitch <= configuration.standMaxPitch + configuration.thresholdAngleTolerance { return .bottom }
        if pitch >= configuration.hingeMinPitch - configuration.thresholdAngleTolerance { return .top }
        return .middle
    }

    private func makeReference(for body: DeadliftBodySide) -> Reference {
        Reference(hip: body.hip, torsoLength: max(ArmGeometry.distance(body.hip, body.shoulder), 1),
                  facing: body.facing)
    }

    private func updateReference(zone: MovementZone, live: Reference, at time: TimeInterval) {
        if tracker.confirmed == .bottom, zone == .bottom {
            lockedReference = live
            awayFromStartSince = nil
            return
        }
        guard lockedReference != nil else { return }
        let since = awayFromStartSince ?? time
        awayFromStartSince = since
        if time - since > configuration.referenceTimeout {
            lockedReference = nil
            awayFromStartSince = nil
        }
    }

    /// Each short horizontal line is centered on the shoulder position predicted from the locked standing
    /// hip and torso length at that line's pitch.
    private func makeThresholds(body: DeadliftBodySide, reference: Reference) -> ArmThresholds {
        func line(pitch: Double, label: String) -> ThresholdLine {
            let radians = pitch * .pi / 180
            let facing = abs(body.shoulder.x - body.hip.x) > 3
                ? (body.shoulder.x >= body.hip.x ? CGFloat(1) : CGFloat(-1))
                : reference.facing
            let shoulder = CGPoint(
                x: reference.hip.x + facing * reference.torsoLength * CGFloat(sin(radians)),
                y: reference.hip.y - reference.torsoLength * CGFloat(cos(radians))
            )
            let halfWidth = configuration.thresholdHalfWidthTorsoRatio * reference.torsoLength
            return ThresholdLine(from: CGPoint(x: shoulder.x - halfWidth, y: shoulder.y),
                                 to: CGPoint(x: shoulder.x + halfWidth, y: shoulder.y), label: label)
        }

        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(pitch: configuration.standMaxPitch, label: "Stand ↑"),
                             topLine: line(pitch: configuration.hingeMinPitch, label: "Hinge ↓"),
                             isLocked: lockedReference != nil, confirmed: confirmed)
    }

    private func resetTracking() {
        tracker.reset()
        cycle = .awaitingStart
        lockedReference = nil
        awayFromStartSince = nil
        formMonitor.invalidate()
    }

    private static func torsoPitch(hip: CGPoint, shoulder: CGPoint) -> Double {
        let dx = abs(shoulder.x - hip.x)
        let dy = abs(hip.y - shoulder.y)
        return Double(atan2(dx, dy)) * 180 / .pi
    }
}

/// The near side is whichever complete shoulder, hip, knee, and ankle set is most confident. It sticks with
/// that side until the other complete side is clearly more confident, like `NearArmSelector`.
private struct DeadliftNearSideSelector {
    private(set) var side: BodySide?

    mutating func select(in frame: PoseFrame, minimumConfidence: Double,
                         switchMargin: Double) -> (body: DeadliftBodySide, switched: Bool)? {
        let candidates = BodySide.allCases.compactMap { side -> DeadliftBodySide? in
            guard let shoulder = frame.point(side.shoulder, minimumConfidence: minimumConfidence),
                  let hip = frame.point(side.hip, minimumConfidence: minimumConfidence),
                  let knee = frame.point(side.knee, minimumConfidence: minimumConfidence),
                  let ankle = frame.point(side.ankle, minimumConfidence: minimumConfidence) else { return nil }
            let joints = [side.shoulder, side.hip, side.knee, side.ankle]
            let confidence = joints.compactMap { frame.pose[$0]?.confidence }.min() ?? 0
            let nose = frame.point(.nose, minimumConfidence: minimumConfidence)
            let torsoDX = shoulder.x - hip.x
            let facing = nose.map { $0.x >= hip.x ? CGFloat(1) : CGFloat(-1) }
                ?? (abs(torsoDX) > 3 ? (torsoDX >= 0 ? CGFloat(1) : CGFloat(-1)) : CGFloat(1))
            return DeadliftBodySide(side: side, shoulder: shoulder, hip: hip, knee: knee, ankle: ankle,
                                    wrist: frame.point(side.wrist, minimumConfidence: minimumConfidence),
                                    confidence: confidence, facing: facing)
        }
        guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else { return nil }
        var selected = best
        if let current = candidates.first(where: { $0.side == side }),
           best.confidence - current.confidence < switchMargin {
            selected = current
        }
        let switched = selected.side != side
        side = selected.side
        return (selected, switched)
    }
}

private struct DeadliftBodySide {
    let side: BodySide
    let shoulder: CGPoint
    let hip: CGPoint
    let knee: CGPoint
    let ankle: CGPoint
    let wrist: CGPoint?
    let confidence: Double
    let facing: CGFloat
}

/// Watches each hinge attempt for shallow depth, excess knee bend, incomplete standing, and weight drift.
/// These observations never affect rep counting.
struct StiffLegDeadliftFormMonitor {
    struct Sample {
        let pitch: Double
        let kneeAngle: Double
        let hip: CGPoint
        let knee: CGPoint
        let ankle: CGPoint
        let wrist: CGPoint?
        let thighLength: CGFloat
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct Attempt {
        let standingPitch: Double
        var peakPitch: Double
        /// The knee angle at the deepest hinge (the attempt's peak pitch).
        var kneeAngleAtPeak: Double?
        var reachedHinge = false
        var retreatedAfterHinge = false
        var rehingedWithoutStanding = false
    }

    private let configuration: StiffLegDeadliftConfiguration
    private var standingPitch: Double?
    private var attempt: Attempt?
    private var lastPeakPitch: Double?
    private var lastKneeAngle: Double?
    private var lastWeightGap: Double?

    init(configuration: StiffLegDeadliftConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, sample: Sample, zone: MovementZone,
                         confirmed: MovementZone?, counting: Bool) -> Output {
        var output = Output()
        let settled = zone == .bottom && confirmed == .bottom
        if counting, settled, let attempt {
            let flags = finish(attempt)
            output.repForms.append(RepForm(timestamp: time, flags: flags))
            self.attempt = nil
        }

        if settled {
            standingPitch = sample.pitch
            if !counting { attempt = nil }
        } else if counting, var active = attempt {
            if sample.pitch > active.peakPitch {
                active.peakPitch = sample.pitch
                active.kneeAngleAtPeak = sample.kneeAngle
            }
            if sample.pitch >= configuration.hingeMinPitch { active.reachedHinge = true }
            if active.reachedHinge,
               active.peakPitch - sample.pitch >= configuration.incompleteHingeRetreat {
                active.retreatedAfterHinge = true
            }
            if active.retreatedAfterHinge, sample.pitch >= configuration.hingeMinPitch {
                active.rehingedWithoutStanding = true
            }
            attempt = active
        } else if counting, let standingPitch,
                  sample.pitch - standingPitch >= configuration.attemptMinimumRise {
            var active = Attempt(standingPitch: standingPitch, peakPitch: sample.pitch)
            active.kneeAngleAtPeak = sample.kneeAngle
            active.reachedHinge = sample.pitch >= configuration.hingeMinPitch
            attempt = active
        } else if !counting {
            attempt = nil
        }

        let weightGap = horizontalWeightGap(sample)
        lastWeightGap = weightGap
        if counting, sample.pitch >= configuration.weightsCloseMinimumPitch,
           let weightGap, weightGap > configuration.weightsCloseMaximumThighRatio {
            output.signals.insert(.deadliftWeightsClose)
        }
        return output
    }

    mutating func invalidate() {
        standingPitch = nil
        attempt = nil
        lastPeakPitch = nil
        lastKneeAngle = nil
        lastWeightGap = nil
    }

    var readings: [FormReading] {
        func value(_ number: Double?, suffix: String = "") -> String {
            number.map { String(format: "%.0f", $0) + suffix } ?? "–"
        }
        return [
            FormReading(label: "Peak θ", value: value(lastPeakPitch, suffix: "°")),
            FormReading(label: "Knee", value: value(lastKneeAngle, suffix: "°")),
            FormReading(label: "Weights", value: lastWeightGap.map { String(format: "%.2f", $0) } ?? "–")
        ]
    }

    private mutating func finish(_ attempt: Attempt) -> Set<CoachingCueID> {
        lastPeakPitch = attempt.peakPitch
        lastKneeAngle = attempt.kneeAngleAtPeak
        var flags: Set<CoachingCueID> = []
        if attempt.peakPitch - attempt.standingPitch >= configuration.attemptMinimumRise,
           !attempt.reachedHinge {
            flags.insert(.deadliftDeeper)
        }
        if let knee = attempt.kneeAngleAtPeak, knee < configuration.squatKneeAngleMaximum {
            flags.insert(.deadliftHipsBack)
        }
        if attempt.rehingedWithoutStanding { flags.insert(.deadliftStandTall) }
        return flags
    }

    /// Horizontal distance from the wrist to the shin at the same height, divided by standing thigh length.
    private func horizontalWeightGap(_ sample: Sample) -> Double? {
        guard let wrist = sample.wrist, sample.thighLength > 1 else { return nil }
        let shinHeight = sample.ankle.y - sample.knee.y
        let fraction: CGFloat
        if abs(shinHeight) < 0.001 {
            fraction = 0
        } else {
            fraction = max(0, min(1, (wrist.y - sample.knee.y) / shinHeight))
        }
        let shinX = sample.knee.x + (sample.ankle.x - sample.knee.x) * fraction
        return Double(abs(wrist.x - shinX) / sample.thighLength)
    }
}
