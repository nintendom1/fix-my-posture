import CoreGraphics
import Foundation

/// Counts a lateral raise only when both arms reach the side and return to the hanging start.
/// Each arm has its own hysteresis tracker and locked shoulder reference.
final class LateralRaiseAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: LateralRaiseConfiguration
    private var trackers: [BodySide: HysteresisPhaseTracker]
    private var cycle: Cycle = .awaitingStart
    private var lastCompleteSample: TimeInterval?
    private var recentArmLengths: [BodySide: [CGFloat]] = [:]
    private var smoothedShoulderY: [BodySide: CGFloat] = [:]
    private var lockedReference: [BodySide: Reference] = [:]
    private var awayFromStartSince: [BodySide: TimeInterval] = [:]
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: LateralRaiseFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedTop: Set<BodySide>)
    }

    /// The shoulder height and longest recent arm length used for one arm's measurements.
    private struct Reference {
        var shoulderY: CGFloat
        var ruler: CGFloat
    }

    init(epoch: Int, configuration: LateralRaiseConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        trackers = [
            .left: HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples),
            .right: HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        ]
        formMonitor = LateralRaiseFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        let confidence = configuration.minimumJointConfidence
        guard let left = ArmGeometry.arm(.left, in: frame, minimumConfidence: confidence),
              let right = ArmGeometry.arm(.right, in: frame, minimumConfidence: confidence) else {
            var analysis = ExerciseAnalysis()
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }

        let time = frame.timestamp
        var rejections: [RepRejection] = []
        if let lastCompleteSample, time - lastCompleteSample > configuration.maximumSampleGap {
            if case .active(_, let reachedTop) = cycle, let lost = RepRejection.lost(at: time, .trackingGap(
                seconds: time - lastCompleteSample, maximum: configuration.maximumSampleGap,
                stage: .of(reachedEnd: !reachedTop.isEmpty,
                           zones: BodySide.allCases.map { trackers[$0]?.lastZone ?? .bottom }))) {
                rejections.append(lost)
            }
            invalidateCycleAndReferences()
        }
        lastCompleteSample = time

        var analysis = ExerciseAnalysis()
        analysis.rejections = rejections
        var zones: [BodySide: MovementZone] = [:]
        var newlyConfirmed: [BodySide: MovementZone] = [:]
        var formSamples: [BodySide: LateralRaiseFormMonitor.ArmSample] = [:]
        var rulers: [CGFloat] = []

        for (side, arm, other) in [(BodySide.left, left, right), (.right, right, left)] {
            let live = liveReference(for: side, arm: arm)
            let reference = lockedReference[side] ?? live
            let height = Double((reference.shoulderY - arm.wrist.y) / reference.ruler)
            let outward = Double(abs(arm.wrist.x - arm.shoulder.x) / reference.ruler)
            let zone = classify(height: height, outward: outward)
            zones[side] = zone
            analysis.readings[side] = ArmReading(signal: height, elbowAngle: arm.elbowAngle, zone: zone)
            if let confirmed = trackers[side]?.update(zone) { newlyConfirmed[side] = confirmed }
            formSamples[side] = .init(height: height, zone: zone,
                                      confirmed: trackers[side]?.confirmed, elbowAngle: arm.elbowAngle)
            rulers.append(reference.ruler)
            updateLock(for: side, zone: zone, height: height, live: live, at: time)
            analysis.thresholds[side] = thresholds(for: side, shoulderX: arm.shoulder.x,
                                                   otherShoulderX: other.shoulder.x, live: live)
        }
        lastThresholds = analysis.thresholds

        let bothAtStart = BodySide.allCases.allSatisfy {
            zones[$0] == .bottom && trackers[$0]?.confirmed == .bottom
        }
        analysis.endPositionSides = Set(BodySide.allCases.filter { trackers[$0]?.confirmed == .top })
        analysis.startPositionHeld = bothAtStart

        let estimatedArmJoint = !frame.estimatedJoints.isDisjoint(with: Set(BodySide.allCases.flatMap(\.armJoints)))
        if estimatedArmJoint {
            // Rep counting can use a completed pose, but form checks must not trust estimated arms.
            formMonitor.invalidate()
            analysis.formReadings = formMonitor.readings
        } else {
            let shoulderGap = estimatedNoseGap(frame, left: left, right: right)
            let form = formMonitor.update(
                at: time,
                arms: formSamples,
                shoulderGap: shoulderGap,
                torsoOffset: torsoOffset(frame, left: left, right: right, rulers: rulers),
                counting: counting
            )
            analysis.repForms = form.repForms
            analysis.formSignals = form.signals
            analysis.formReadings = formMonitor.readings
        }

        guard counting else {
            if case .active(_, let reachedTop) = cycle, let lost = RepRejection.lost(at: time, .countingStopped(
                stage: .of(reachedEnd: !reachedTop.isEmpty, zones: zones.values))) {
                analysis.rejections.append(lost)
            }
            cycle = .awaitingStart
            return analysis
        }

        switch cycle {
        case .awaitingStart:
            if bothAtStart { cycle = .active(movementStart: time, reachedTop: []) }
        case .active(var movementStart, var reachedTop):
            if reachedTop.isEmpty, zones.values.allSatisfy({ $0 == .bottom }) {
                movementStart = time
            }
            for (side, zone) in newlyConfirmed where zone == .top {
                reachedTop.insert(side)
            }
            if !reachedTop.isEmpty, bothAtStart {
                let duration = time - movementStart
                if reachedTop.count < BodySide.allCases.count {
                    analysis.rejections.append(RepRejection(timestamp: time, reason: .partialEnd(reached: reachedTop)))
                } else if duration >= configuration.minimumRepDuration {
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                } else {
                    analysis.rejections.append(RepRejection(timestamp: time, reason: .tooFast(
                        duration: duration, minimum: configuration.minimumRepDuration)))
                }
                cycle = .active(movementStart: time, reachedTop: [])
            } else {
                cycle = .active(movementStart: movementStart, reachedTop: reachedTop)
            }
        }
        return analysis
    }

    // MARK: - References and thresholds

    private func liveReference(for side: BodySide, arm: ArmPoints) -> Reference {
        var lengths = recentArmLengths[side] ?? []
        lengths.append(arm.armLength)
        if lengths.count > configuration.rulerWindow {
            lengths.removeFirst(lengths.count - configuration.rulerWindow)
        }
        recentArmLengths[side] = lengths

        let previous = smoothedShoulderY[side] ?? arm.shoulder.y
        let shoulderY = previous + (arm.shoulder.y - previous) * configuration.shoulderSmoothing
        smoothedShoulderY[side] = shoulderY
        return Reference(shoulderY: shoulderY, ruler: max(lengths.max() ?? arm.armLength, 1))
    }

    /// A start reference can refresh only at the deeper hanging rest, not at a near-threshold return.
    /// This keeps Start and Top lines from ratcheting when a return barely satisfies the start rule.
    private func updateLock(for side: BodySide, zone: MovementZone, height: Double,
                            live: Reference, at time: TimeInterval) {
        if trackers[side]?.confirmed == .bottom, zone == .bottom {
            awayFromStartSince[side] = nil
            if lockedReference[side] == nil || height <= configuration.startMaximumHeight - 0.15 {
                lockedReference[side] = live
            }
            return
        }
        guard lockedReference[side] != nil else { return }
        let since = awayFromStartSince[side] ?? time
        awayFromStartSince[side] = since
        if time - since > configuration.referenceTimeout {
            lockedReference[side] = nil
            awayFromStartSince[side] = nil
        }
    }

    private func thresholds(for side: BodySide, shoulderX: CGFloat, otherShoulderX: CGFloat,
                            live: Reference) -> ArmThresholds {
        let reference = lockedReference[side] ?? live
        let outward: CGFloat = shoulderX >= otherShoulderX ? 1 : -1
        func line(height: Double, label: String) -> ThresholdLine {
            let y = reference.shoulderY - CGFloat(height) * reference.ruler
            return ThresholdLine(from: CGPoint(x: shoulderX - outward * 0.1 * reference.ruler, y: y),
                                 to: CGPoint(x: shoulderX + outward * 0.8 * reference.ruler, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch trackers[side]?.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(
            startLine: line(height: configuration.startMaximumHeight, label: "Start ↓"),
            topLine: line(height: configuration.topMinimumHeight, label: "Top ↑"),
            isLocked: lockedReference[side] != nil,
            confirmed: confirmed
        )
    }

    private func torsoOffset(_ frame: PoseFrame, left: ArmPoints, right: ArmPoints,
                             rulers: [CGFloat]) -> Double? {
        let confidence = configuration.minimumJointConfidence
        guard let leftHip = frame.point(.leftHip, minimumConfidence: confidence),
              let rightHip = frame.point(.rightHip, minimumConfidence: confidence),
              !rulers.isEmpty else { return nil }
        let ruler = rulers.reduce(0, +) / CGFloat(rulers.count)
        let shoulders = ArmGeometry.midpoint(left.shoulder, right.shoulder)
        let hips = ArmGeometry.midpoint(leftHip, rightHip)
        return Double((shoulders.x - hips.x) / ruler)
    }

    /// Shrug height is the nose-to-shoulder-midpoint gap in shoulder widths.
    private func estimatedNoseGap(_ frame: PoseFrame, left: ArmPoints, right: ArmPoints) -> Double? {
        guard !frame.estimatedJoints.contains(.nose),
              let nose = frame.point(.nose, minimumConfidence: configuration.minimumJointConfidence) else { return nil }
        let width = ArmGeometry.distance(left.shoulder, right.shoulder)
        guard width > 1 else { return nil }
        let shoulders = ArmGeometry.midpoint(left.shoulder, right.shoulder)
        return Double((shoulders.y - nose.y) / width)
    }

    // MARK: - Counting

    private func classify(height: Double, outward: Double) -> MovementZone {
        let tolerance = 1e-9
        if height <= configuration.startMaximumHeight + tolerance { return .bottom }
        if height >= configuration.topMinimumHeight - tolerance
            && outward >= configuration.topMinimumOutward - tolerance { return .top }
        return .middle
    }

    private func invalidateCycleAndReferences() {
        cycle = .awaitingStart
        formMonitor.invalidate()
        for side in BodySide.allCases { trackers[side]?.reset() }
        recentArmLengths = [:]
        smoothedShoulderY = [:]
        lockedReference = [:]
        awayFromStartSince = [:]
        lastThresholds = [:]
    }
}

/// Observes form separately from counting so a cue can explain an attempt that did not count.
struct LateralRaiseFormMonitor {
    struct ArmSample {
        let height: Double
        let zone: MovementZone
        let confirmed: MovementZone?
        let elbowAngle: Double
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct ArmAttempt {
        var startHeight: Double
        var peakHeight: Double
        var reachedTop = false
        var topCrossing: TimeInterval?
        var peakTopElbowAngle: Double?
    }

    private struct Attempt {
        var arms: [BodySide: ArmAttempt]
        var started = false
        var maximumHeightGap = 0.0
        var shoulderGapAtStart: Double?
        var maximumShrug = 0.0
    }

    private struct Summary {
        var timingGap: TimeInterval?
        var heightGap: Double
        var elbowAngle: Double?
        var shrug: Double?
    }

    private let configuration: LateralRaiseConfiguration
    private var attempt: Attempt?
    private var settledSamples = 0
    private var torsoBaseline: [Double] = []
    private var torsoDeviation: Double?
    private var currentShrug: Double?
    private var lastSummary: Summary?

    init(configuration: LateralRaiseConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, arms: [BodySide: ArmSample], shoulderGap: Double?,
                         torsoOffset: Double?, counting: Bool) -> Output {
        var output = Output()
        let bothAtStart = BodySide.allCases.allSatisfy {
            arms[$0]?.zone == .bottom && arms[$0]?.confirmed == .bottom
        }
        updateTorso(torsoOffset, bothAtStart: bothAtStart)
        if counting, let torsoDeviation, abs(torsoDeviation) > configuration.torsoOffsetTolerance {
            output.signals.insert(.lateralTorsoCentered)
        }

        guard counting else {
            attempt = nil
            currentShrug = nil
            return output
        }

        let bothNearTop = BodySide.allCases.allSatisfy { (arms[$0]?.height ?? -.infinity) >= -0.4 }
        if bothNearTop, let baseline = attempt?.shoulderGapAtStart, let shoulderGap,
           baseline - shoulderGap > configuration.shoulderShrugTolerance {
            currentShrug = baseline - shoulderGap
            output.signals.insert(.lateralShouldersDown)
            if var current = attempt {
                current.maximumShrug = max(current.maximumShrug, baseline - shoulderGap)
                attempt = current
            }
        } else {
            currentShrug = nil
        }

        if bothAtStart, let current = attempt, current.started {
            output.repForms.append(finish(current, at: time))
            attempt = Attempt(arms: arms.mapValues {
                ArmAttempt(startHeight: $0.height, peakHeight: $0.height)
            }, shoulderGapAtStart: shoulderGap)
            settledSamples = configuration.confirmationSamples
            return output
        }

        settledSamples = bothAtStart ? settledSamples + 1 : 0
        if settledSamples >= configuration.confirmationSamples {
            var waiting = Attempt(arms: arms.mapValues {
                ArmAttempt(startHeight: $0.height, peakHeight: $0.height)
            }, shoulderGapAtStart: shoulderGap)
            if let previous = attempt {
                if previous.started {
                    output.repForms.append(finish(previous, at: time))
                } else {
                    for side in BodySide.allCases {
                        guard let oldHeight = previous.arms[side]?.startHeight else { continue }
                        guard var arm = waiting.arms[side] else { continue }
                        arm.startHeight = min(oldHeight, arm.startHeight)
                        waiting.arms[side] = arm
                    }
                    waiting.shoulderGapAtStart = previous.shoulderGapAtStart ?? shoulderGap
                }
            }
            attempt = waiting
            return output
        }
        guard var current = attempt else { return output }

        for side in BodySide.allCases {
            guard let sample = arms[side], var arm = current.arms[side] else { continue }
            arm.peakHeight = max(arm.peakHeight, sample.height)
            if sample.height >= arm.startHeight + configuration.attemptMinimumRise { current.started = true }
            if sample.zone == .top {
                arm.reachedTop = true
                arm.peakTopElbowAngle = max(arm.peakTopElbowAngle ?? sample.elbowAngle, sample.elbowAngle)
                if arm.topCrossing == nil { arm.topCrossing = time }
            }
            current.arms[side] = arm
        }

        let bothCrossedTop = current.arms.values.allSatisfy(\.reachedTop)
        if !bothCrossedTop, let left = arms[.left], let right = arms[.right],
           BodySide.allCases.contains(where: { side in
               guard let arm = current.arms[side], let sample = arms[side] else { return false }
               return sample.height >= arm.startHeight + configuration.attemptMinimumRise
           }) {
            current.maximumHeightGap = max(current.maximumHeightGap, abs(left.height - right.height))
        }
        attempt = current
        return output
    }

    mutating func invalidate() {
        attempt = nil
        settledSamples = 0
        currentShrug = nil
    }

    var readings: [FormReading] {
        func format(_ value: Double?, _ pattern: String) -> String {
            value.map { String(format: pattern, $0) } ?? "–"
        }
        return [
            FormReading(label: "Δt", value: format(lastSummary?.timingGap, "%.2fs")),
            FormReading(label: "Δh", value: format(lastSummary?.heightGap, "%.2f")),
            FormReading(label: "ext", value: format(lastSummary?.elbowAngle, "%.0f°")),
            FormReading(label: "shrug", value: format(currentShrug ?? lastSummary?.shrug, "%.2f")),
            FormReading(label: "torso", value: format(torsoDeviation.map(abs), "%.2f"))
        ]
    }

    private mutating func finish(_ attempt: Attempt, at time: TimeInterval) -> RepForm {
        var flags: Set<CoachingCueID> = []
        let arms = BodySide.allCases.compactMap { attempt.arms[$0] }
        let raisedEnough = arms.contains { $0.peakHeight >= $0.startHeight + configuration.attemptMinimumRise }
        if raisedEnough, arms.contains(where: { !$0.reachedTop }) {
            flags.insert(.lateralHigher)
        }

        let topTimes = arms.compactMap(\.topCrossing)
        let timingGap = topTimes.count == BodySide.allCases.count
            ? (topTimes.max() ?? 0) - (topTimes.min() ?? 0)
            : nil
        if (timingGap ?? 0) > configuration.maximumTopTimingGap
            || attempt.maximumHeightGap > configuration.maximumHeightGap {
            flags.insert(.lateralEven)
        }

        let lowestTopAngle = arms.compactMap(\.peakTopElbowAngle).min()
        if let lowestTopAngle, lowestTopAngle < configuration.minimumTopElbowAngle {
            flags.insert(.lateralArmsLong)
        }
        let shrug = attempt.maximumShrug > 0 ? attempt.maximumShrug : nil
        lastSummary = Summary(timingGap: timingGap, heightGap: attempt.maximumHeightGap,
                              elbowAngle: lowestTopAngle, shrug: shrug)
        return RepForm(timestamp: time, flags: flags)
    }

    private mutating func updateTorso(_ offset: Double?, bothAtStart: Bool) {
        guard let offset else {
            torsoDeviation = nil
            return
        }
        if bothAtStart, torsoBaseline.count < configuration.baselineSamples {
            torsoBaseline.append(offset)
        }
        guard torsoBaseline.count >= configuration.baselineSamples, !torsoBaseline.isEmpty else {
            torsoDeviation = nil
            return
        }
        torsoDeviation = offset - torsoBaseline.reduce(0, +) / Double(torsoBaseline.count)
    }
}
