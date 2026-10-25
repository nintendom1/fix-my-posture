import CoreGraphics
import Foundation

/// Counts a side-view lunge from the standing hip height to a lowered lunge and back to standing.
/// The event represents one rep for the side the session is currently running; Vision's side names do
/// not identify which leg stepped back in a profile view.
final class RearLungeAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: RearLungeConfiguration
    private var nearSide = RearLungeNearSideSelector()
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var recentLegLengths: [LegLengthSample] = []
    private var lockedReference: Reference?
    private var cycle: Cycle = .awaitingStart
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: RearLungeFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedLunge: Bool)
    }

    private struct Reference {
        let hip: CGPoint
        let legLength: CGFloat
    }

    private struct LegLengthSample {
        let time: TimeInterval
        let length: CGFloat
    }

    init(epoch: Int, configuration: RearLungeConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = RearLungeFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        guard let selection = nearSide.select(in: frame,
                                              minimumConfidence: configuration.minimumJointConfidence,
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

        let hip = signalHip(in: frame, fallback: body.hip)
        let shoulder = signalShoulder(in: frame, fallback: body.shoulder)
        let legLength = max(ArmGeometry.distance(body.hip, body.knee)
                            + ArmGeometry.distance(body.knee, body.ankle), 1)
        appendLegLength(legLength, at: time)
        let liveReference = Reference(hip: hip, legLength: recentLegLengths.map(\.length).max() ?? legLength)
        let comparison = lockedReference ?? liveReference
        let drop = Double((hip.y - comparison.hip.y) / comparison.legLength)
        let zone = classify(drop)
        let newlyConfirmed = tracker.update(zone)
        updateReference(zone: zone, live: liveReference, newlyConfirmed: newlyConfirmed, counting: counting)
        let reference = lockedReference ?? liveReference

        lastThresholds = [body.side: makeThresholds(reference: reference)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? [body.side] : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let formJoints: Set<LandmarkType> = [.leftShoulder, .rightShoulder, .leftHip, .rightHip,
                                             .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        if !frame.estimatedJoints.isDisjoint(with: formJoints) {
            formMonitor.invalidate()
        }
        let stepRatio = horizontalAnkleGap(in: frame).map { Double($0 / reference.legLength) }
        let torsoPitch = shoulder.map { Self.torsoPitch(hip: hip, shoulder: $0) }
        let form = formMonitor.update(
            at: time,
            sample: .init(drop: drop, stepRatio: stepRatio, torsoPitch: torsoPitch),
            zone: zone,
            confirmed: tracker.confirmed,
            counting: counting
        )
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
                cycle = .active(movementStart: time, reachedLunge: false)
            }
        case .active(var movementStart, var reachedLunge):
            if !reachedLunge, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedLunge = true }
            if newlyConfirmed == .bottom {
                if reachedLunge, time - movementStart >= configuration.minimumRepDuration {
                    // One lunge counts in the set side selected by the session. The Vision labels below
                    // are only used to choose reliable geometry and are not the stepping leg.
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time,
                                                       sides: Set(BodySide.allCases)))
                }
                movementStart = time
                reachedLunge = false
            }
            cycle = .active(movementStart: movementStart, reachedLunge: reachedLunge)
        }
        return analysis
    }

    private func classify(_ drop: Double) -> MovementZone {
        if drop <= configuration.standMaxDrop + configuration.thresholdTolerance { return .bottom }
        if drop >= configuration.lungeMinDrop - configuration.thresholdTolerance { return .top }
        return .middle
    }

    private func signalHip(in frame: PoseFrame, fallback: CGPoint) -> CGPoint {
        guard let left = frame.point(.leftHip, minimumConfidence: configuration.minimumJointConfidence),
              let right = frame.point(.rightHip, minimumConfidence: configuration.minimumJointConfidence) else {
            return fallback
        }
        return ArmGeometry.midpoint(left, right)
    }

    private func signalShoulder(in frame: PoseFrame, fallback: CGPoint) -> CGPoint? {
        if let left = frame.point(.leftShoulder, minimumConfidence: configuration.minimumJointConfidence),
           let right = frame.point(.rightShoulder, minimumConfidence: configuration.minimumJointConfidence) {
            return ArmGeometry.midpoint(left, right)
        }
        return fallback
    }

    private func appendLegLength(_ length: CGFloat, at time: TimeInterval) {
        recentLegLengths.append(LegLengthSample(time: time, length: length))
        recentLegLengths.removeAll { time - $0.time > configuration.rulerWindow }
    }

    private func horizontalAnkleGap(in frame: PoseFrame) -> CGFloat? {
        guard let left = frame.point(.leftAnkle, minimumConfidence: configuration.minimumJointConfidence),
              let right = frame.point(.rightAnkle, minimumConfidence: configuration.minimumJointConfidence) else {
            return nil
        }
        return abs(left.x - right.x)
    }

    /// The standing reference is set at the first confirmed Stand. While the user stays settled at Stand it may
    /// only rise toward the true upright hip during a set, so a return that stops just inside the Stand line can
    /// never ratchet the baseline down rep after rep. Between sets it follows the standing user freely.
    private func updateReference(zone: MovementZone, live: Reference, newlyConfirmed: MovementZone?,
                                 counting: Bool) {
        guard let locked = lockedReference else {
            if newlyConfirmed == .bottom { lockedReference = live }
            return
        }
        guard tracker.confirmed == .bottom, zone == .bottom else { return }
        if !counting || live.hip.y < locked.hip.y {
            lockedReference = live
        }
    }

    /// Horizontal lines centered over the hips at the standing and lunge drop thresholds.
    private func makeThresholds(reference: Reference) -> ArmThresholds {
        func line(drop: Double, label: String) -> ThresholdLine {
            let y = reference.hip.y + CGFloat(drop) * reference.legLength
            let halfWidth = configuration.thresholdHalfWidthLegRatio * reference.legLength
            return ThresholdLine(from: CGPoint(x: reference.hip.x - halfWidth, y: y),
                                 to: CGPoint(x: reference.hip.x + halfWidth, y: y), label: label)
        }

        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(drop: configuration.standMaxDrop, label: "Stand ↑"),
                             topLine: line(drop: configuration.lungeMinDrop, label: "Lunge ↓"),
                             isLocked: lockedReference != nil, confirmed: confirmed)
    }

    /// A gap or a switch to the other side can come with a new position or distance, so the standing reference
    /// and the leg ruler are measured afresh.
    private func resetTracking() {
        tracker.reset()
        cycle = .awaitingStart
        lockedReference = nil
        recentLegLengths.removeAll()
        formMonitor.invalidate()
    }

    private static func torsoPitch(hip: CGPoint, shoulder: CGPoint) -> Double {
        let dx = abs(shoulder.x - hip.x)
        let dy = abs(hip.y - shoulder.y)
        return Double(atan2(dx, dy)) * 180 / .pi
    }
}

/// Selects a complete side for geometry and sticks to it through ordinary confidence changes.
private struct RearLungeNearSideSelector {
    private(set) var side: BodySide?

    mutating func select(in frame: PoseFrame, minimumConfidence: Double,
                         switchMargin: Double) -> (body: RearLungeBodySide, switched: Bool)? {
        let candidates = BodySide.allCases.compactMap { side -> RearLungeBodySide? in
            guard let shoulder = frame.point(side.shoulder, minimumConfidence: minimumConfidence),
                  let hip = frame.point(side.hip, minimumConfidence: minimumConfidence),
                  let knee = frame.point(side.knee, minimumConfidence: minimumConfidence),
                  let ankle = frame.point(side.ankle, minimumConfidence: minimumConfidence) else { return nil }
            let confidence = [side.shoulder, side.hip, side.knee, side.ankle]
                .compactMap { frame.pose[$0]?.confidence }.min() ?? 0
            return RearLungeBodySide(side: side, shoulder: shoulder, hip: hip, knee: knee,
                                     ankle: ankle, confidence: confidence)
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

private struct RearLungeBodySide {
    let side: BodySide
    let shoulder: CGPoint
    let hip: CGPoint
    let knee: CGPoint
    let ankle: CGPoint
    let confidence: Double
}

/// Observes the attempt for range, step length, return to standing, and torso lean.
struct RearLungeFormMonitor {
    struct Sample {
        let drop: Double
        let stepRatio: Double?
        let torsoPitch: Double?
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct Attempt {
        var peakDrop: Double
        var deepestStepRatio: Double?
        var reachedLunge: Bool
        var roseAfterLunge = false
        var lowestDropAfterRise: Double?
        var reachedStandAfterLunge = false
        var reloweredWithoutStanding = false
    }

    private let configuration: RearLungeConfiguration
    private var attempt: Attempt?
    private var lastDrop: Double?
    private var lastStepRatio: Double?
    private var lastTorsoPitch: Double?

    init(configuration: RearLungeConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, sample: Sample, zone: MovementZone,
                         confirmed: MovementZone?, counting: Bool) -> Output {
        var output = Output()
        let settled = zone == .bottom && confirmed == .bottom
        if counting, settled, let attempt {
            output.repForms.append(RepForm(timestamp: time, flags: finish(attempt)))
            self.attempt = nil
        }

        if settled {
            if !counting { attempt = nil }
        } else if counting {
            if var active = attempt {
                if sample.drop >= active.peakDrop {
                    active.peakDrop = sample.drop
                    active.deepestStepRatio = sample.stepRatio
                }
                if sample.drop >= configuration.lungeMinDrop { active.reachedLunge = true }
                if active.reachedLunge, active.peakDrop - sample.drop >= configuration.returnRise {
                    active.roseAfterLunge = true
                    active.lowestDropAfterRise = min(active.lowestDropAfterRise ?? sample.drop, sample.drop)
                }
                if active.reachedLunge, sample.drop <= configuration.standMaxDrop {
                    active.reachedStandAfterLunge = true
                }
                if active.roseAfterLunge, !active.reachedStandAfterLunge,
                   let lowestDrop = active.lowestDropAfterRise,
                   sample.drop - lowestDrop >= configuration.relowerMinimum {
                    active.reloweredWithoutStanding = true
                }
                if active.roseAfterLunge {
                    active.lowestDropAfterRise = min(active.lowestDropAfterRise ?? sample.drop, sample.drop)
                }
                attempt = active
            } else if sample.drop >= configuration.attemptMinimumDrop {
                attempt = Attempt(peakDrop: sample.drop, deepestStepRatio: sample.stepRatio,
                                  reachedLunge: sample.drop >= configuration.lungeMinDrop)
            }
        } else {
            attempt = nil
        }

        lastDrop = sample.drop
        lastStepRatio = sample.stepRatio
        lastTorsoPitch = sample.torsoPitch
        if counting, sample.drop >= configuration.chestCueMinimumDrop,
           let torsoPitch = sample.torsoPitch, torsoPitch > configuration.chestLeanDegrees {
            output.signals.insert(.lungeChestUp)
        }
        return output
    }

    mutating func invalidate() {
        attempt = nil
        lastDrop = nil
        lastStepRatio = nil
        lastTorsoPitch = nil
    }

    var readings: [FormReading] {
        func value(_ number: Double?, suffix: String = "") -> String {
            number.map { String(format: "%.2f", $0) + suffix } ?? "–"
        }
        return [
            FormReading(label: "Drop d", value: value(lastDrop)),
            FormReading(label: "Step", value: value(lastStepRatio)),
            FormReading(label: "Torso θ", value: value(lastTorsoPitch, suffix: "°"))
        ]
    }

    private func finish(_ attempt: Attempt) -> Set<CoachingCueID> {
        var flags: Set<CoachingCueID> = []
        if attempt.peakDrop >= configuration.attemptMinimumDrop, !attempt.reachedLunge {
            flags.insert(.lungeDeeper)
        }
        if let stepRatio = attempt.deepestStepRatio, stepRatio < configuration.minimumStepRatio {
            flags.insert(.lungeStepLonger)
        }
        if attempt.reloweredWithoutStanding { flags.insert(.lungeStandTall) }
        return flags
    }
}
