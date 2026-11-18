import CoreGraphics
import Foundation

/// Counts hammer curls from the front, one arm at a time. Each arm has its own hysteresis tracker and
/// earns a rep when it hangs straight, curls past the Top line, and hangs straight again, so arms can
/// alternate or move together. The session shows the reps both arms have done.
///
/// Heights are the wrist above its elbow in that arm's upper-arm length. While an arm hangs at the start,
/// its elbow height and ruler are locked until it returns, so the lines hold still during the curl.
final class HammerCurlAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: HammerCurlConfiguration
    private var arms: [BodySide: ArmState] = [:]
    private var formMonitor: HammerCurlFormMonitor
    /// The last frame processed without counting. An arm unseen since then would have lost its attempt.
    private var countingStoppedAt: TimeInterval?

    private struct ArmState {
        var tracker: HysteresisPhaseTracker
        var lastSample: TimeInterval?
        /// When the tracker last confirmed the start.
        var startConfirmedAt: TimeInterval?
        var recentUpperArms: [CGFloat] = []
        var smoothedElbowY: CGFloat?
        var locked: Reference?
        var awayFromStartSince: TimeInterval?
        var cycle: Cycle = .awaitingBottom
        var thresholds: ArmThresholds?
    }

    private enum Cycle {
        case awaitingBottom
        /// `movementStart` is the last time the arm hung at the start before it reached the top; `topReachedAt` is
        /// when it reached the top, nil until then.
        case active(movementStart: TimeInterval, topReachedAt: TimeInterval?)
    }

    /// The elbow height and upper-arm length one arm's heights are measured from.
    private struct Reference {
        var elbowY: CGFloat
        var ruler: CGFloat
    }

    init(epoch: Int, configuration: HammerCurlConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        formMonitor = HammerCurlFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        let time = frame.timestamp
        var formSamples: [BodySide: HammerCurlFormMonitor.ArmSample] = [:]
        var points: [BodySide: ArmPoints] = [:]
        var rulers: [CGFloat] = []
        if !counting { countingStoppedAt = time }

        for side in BodySide.allCases {
            var state = arms[side] ?? ArmState(tracker: HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples))
            defer { arms[side] = state }
            guard let arm = ArmGeometry.arm(side, in: frame, minimumConfidence: configuration.minimumJointConfidence) else {
                // The tracker and lock hold; the gap check decides whether this arm's rep survives.
                if let thresholds = state.thresholds { analysis.thresholds[side] = thresholds }
                continue
            }
            points[side] = arm
            if let last = state.lastSample, time - last > configuration.maximumSampleGap {
                if case .active(_, let topReachedAt) = state.cycle, let lost = RepRejection.lost(at: time, side: side, .trackingGap(
                    seconds: time - last, maximum: configuration.maximumSampleGap,
                    stage: .of(reachedEnd: topReachedAt != nil, zones: [state.tracker.lastZone ?? .bottom]))) {
                    analysis.rejections.append(lost)
                }
                state.tracker.reset()
                state.startConfirmedAt = nil
                state.cycle = .awaitingBottom
                state.locked = nil
                state.awayFromStartSince = nil
                formMonitor.invalidate(side)
            }
            state.lastSample = time

            let live = liveReference(&state, arm: arm)
            let reference = state.locked ?? live
            let ratio = Double((reference.elbowY - arm.wrist.y) / reference.ruler)
            let zone = classify(ratio)
            let newlyConfirmed = state.tracker.update(zone)
            if newlyConfirmed == .bottom { state.startConfirmedAt = time }
            updateLock(&state, zone: zone, live: live, at: time)
            rulers.append(reference.ruler)

            analysis.readings[side] = ArmReading(signal: ratio, elbowAngle: arm.elbowAngle, zone: zone)
            let thresholds = makeThresholds(state, elbowX: arm.elbow.x, outward: outward(side, arm: arm, frame: frame), live: live)
            state.thresholds = thresholds
            analysis.thresholds[side] = thresholds

            if counting {
                let outcome = countRep(&state, zone: zone, newlyConfirmed: newlyConfirmed, at: time)
                if let rep = outcome.rep {
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: rep, sides: [side]))
                }
                if let tooFast = outcome.tooFast {
                    analysis.rejections.append(RepRejection(timestamp: time, side: side, reason: .tooFast(
                        duration: tooFast, minimum: configuration.minimumRepDuration)))
                }
            } else {
                if case .active(_, let topReachedAt) = state.cycle, let lost = RepRejection.lost(at: time, side: side,
                    .countingStopped(stage: .of(reachedEnd: topReachedAt != nil, zones: [zone]))) {
                    analysis.rejections.append(lost)
                }
                state.cycle = .awaitingBottom
            }
            formSamples[side] = .init(ratio: ratio, zone: zone, confirmed: state.tracker.confirmed,
                                      flare: elbowFlare(arm, side: side, frame: frame))
            if !frame.estimatedJoints.isDisjoint(with: Set(side.armJoints)) {
                formMonitor.invalidate(side)
            }
        }

        analysis.endPositionSides = Set(BodySide.allCases.filter { arms[$0]?.tracker.confirmed == .top })
        analysis.startPositionHeld = BodySide.allCases.allSatisfy { arms[$0]?.tracker.confirmed == .bottom }
            && points.count == BodySide.allCases.count

        let form = formMonitor.update(at: time, arms: formSamples, sway: sway(frame, points: points, rulers: rulers),
                                      counting: counting)
        analysis.repForms = form.repForms
        analysis.formSignals = form.signals
        analysis.formReadings = formMonitor.readings
        return analysis
    }

    // MARK: - Counting

    /// The rep's timestamp when this arm completes one, or how long an attempt that came back too fast took.
    private func countRep(_ state: inout ArmState, zone: MovementZone, newlyConfirmed: MovementZone?,
                          at time: TimeInterval) -> (rep: TimeInterval?, tooFast: TimeInterval?) {
        switch state.cycle {
        case .awaitingBottom:
            if state.tracker.confirmed == .bottom { state.cycle = .active(movementStart: time, topReachedAt: nil) }
            return (nil, nil)
        case .active(var movementStart, var topReachedAt):
            if topReachedAt == nil, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { topReachedAt = topReachedAt ?? time }
            var outcome: (rep: TimeInterval?, tooFast: TimeInterval?) = (nil, nil)
            // Only a resumed attempt can be past the top while the tracker holds the start: this view confirmed the
            // return during its warm-up, so the attempt ends on this first counting frame.
            if newlyConfirmed == .bottom || (topReachedAt != nil && state.tracker.confirmed == .bottom) {
                if topReachedAt != nil, time - movementStart >= configuration.minimumRepDuration {
                    outcome.rep = time
                } else if topReachedAt != nil {
                    outcome.tooFast = time - movementStart
                }
                movementStart = time
                topReachedAt = nil
            }
            state.cycle = .active(movementStart: movementStart, topReachedAt: topReachedAt)
            return outcome
        }
    }

    // MARK: - Camera-view hand-off

    /// Arms past the Top line and not yet credited. A hidden arm still carries, as the far arm does during a turn,
    /// unless counting stopped after it was last seen.
    func attemptInProgress() -> RepAttemptInProgress? {
        let carried = BodySide.allCases.compactMap { side -> (side: BodySide, start: TimeInterval, top: TimeInterval)? in
            guard let state = arms[side], case .active(let start, let top?) = state.cycle,
                  let lastSample = state.lastSample,
                  countingStoppedAt.map({ $0 < lastSample }) ?? true else { return nil }
            return (side, start, top)
        }
        guard let start = carried.map(\.start).min(), let end = carried.map(\.top).max() else { return nil }
        return RepAttemptInProgress(movementStart: start, reachedEnd: end, sides: Set(carried.map(\.side)))
    }

    /// Each carried arm continues past the Top line, so it counts once its own tracker confirms the start.
    func resume(_ attempt: RepAttemptInProgress) {
        for side in attempt.sides {
            var state = arms[side] ?? ArmState(tracker: HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples))
            if case .active(_, .some) = state.cycle { continue }
            if state.tracker.confirmed == .bottom, (state.startConfirmedAt ?? -.infinity) <= attempt.reachedEnd { continue }
            state.cycle = .active(movementStart: attempt.movementStart, topReachedAt: attempt.reachedEnd)
            arms[side] = state
        }
    }

    private func classify(_ ratio: Double) -> MovementZone {
        if ratio <= configuration.bottomMaxRatio { return .bottom }
        if ratio >= configuration.topMinRatio { return .top }
        return .middle
    }

    // MARK: - References

    /// Smoothed elbow height and the longest recent upper arm, which resists momentary foreshortening.
    private func liveReference(_ state: inout ArmState, arm: ArmPoints) -> Reference {
        state.recentUpperArms.append(arm.upperArmLength)
        if state.recentUpperArms.count > configuration.rulerWindow {
            state.recentUpperArms.removeFirst(state.recentUpperArms.count - configuration.rulerWindow)
        }
        let previous = state.smoothedElbowY ?? arm.elbow.y
        let elbowY = previous + (arm.elbow.y - previous) * configuration.elbowSmoothing
        state.smoothedElbowY = elbowY
        return Reference(elbowY: elbowY, ruler: max(state.recentUpperArms.max() ?? arm.upperArmLength, 1))
    }

    /// Refreshes the lock while the arm hangs at the start and holds it while the arm curls. A lock held
    /// too long is dropped so the arm can't get stuck.
    private func updateLock(_ state: inout ArmState, zone: MovementZone, live: Reference, at time: TimeInterval) {
        if state.tracker.confirmed == .bottom, zone == .bottom {
            state.locked = live
            state.awayFromStartSince = nil
            return
        }
        guard state.locked != nil else { return }
        let since = state.awayFromStartSince ?? time
        state.awayFromStartSince = since
        if time - since > configuration.referenceTimeout {
            state.locked = nil
            state.awayFromStartSince = nil
        }
    }

    /// The lines cross the wrist's path and reach outward past the arm, where their labels sit.
    private func makeThresholds(_ state: ArmState, elbowX: CGFloat, outward: CGFloat, live: Reference) -> ArmThresholds {
        let reference = state.locked ?? live
        func line(ratio: Double, label: String) -> ThresholdLine {
            let y = reference.elbowY - CGFloat(ratio) * reference.ruler
            return ThresholdLine(from: CGPoint(x: elbowX - outward * 0.3 * reference.ruler, y: y),
                                 to: CGPoint(x: elbowX + outward * 0.9 * reference.ruler, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch state.tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(ratio: configuration.bottomMaxRatio, label: "Start ↓"),
                             topLine: line(ratio: configuration.topMinRatio, label: "Top ↑"),
                             isLocked: state.locked != nil, confirmed: confirmed)
    }

    /// +1 when the arm's outer side has larger x. Unmirrored, the user's left side has the larger x.
    private func outward(_ side: BodySide, arm: ArmPoints, frame: PoseFrame) -> CGFloat {
        let other: BodySide = side == .left ? .right : .left
        guard let otherShoulder = frame.point(other.shoulder, minimumConfidence: configuration.minimumJointConfidence) else {
            return side == .left ? 1 : -1
        }
        return arm.shoulder.x >= otherShoulder.x ? 1 : -1
    }

    // MARK: - Form inputs

    /// Sideways distance from the elbow to its shoulder, in shoulder widths.
    private func elbowFlare(_ arm: ArmPoints, side: BodySide, frame: PoseFrame) -> Double? {
        let other: BodySide = side == .left ? .right : .left
        guard let otherShoulder = frame.point(other.shoulder, minimumConfidence: configuration.minimumJointConfidence) else { return nil }
        let width = ArmGeometry.distance(arm.shoulder, otherShoulder)
        guard width > 1 else { return nil }
        return Double(abs(arm.elbow.x - arm.shoulder.x) / width)
    }

    /// The shoulder midpoint relative to the hip midpoint, in upper-arm lengths; nil without hips.
    private func sway(_ frame: PoseFrame, points: [BodySide: ArmPoints], rulers: [CGFloat]) -> CGVector? {
        let confidence = configuration.minimumJointConfidence
        guard let left = points[.left], let right = points[.right], !rulers.isEmpty,
              let leftHip = frame.point(.leftHip, minimumConfidence: confidence),
              let rightHip = frame.point(.rightHip, minimumConfidence: confidence) else { return nil }
        let ruler = rulers.reduce(0, +) / CGFloat(rulers.count)
        let shoulders = ArmGeometry.midpoint(left.shoulder, right.shoulder)
        let hips = ArmGeometry.midpoint(leftHip, rightHip)
        return CGVector(dx: (shoulders.x - hips.x) / ruler, dy: (shoulders.y - hips.y) / ruler)
    }
}
