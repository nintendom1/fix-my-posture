import CoreGraphics
import Foundation

/// Counts a shrug when both shoulders rise toward the nose and return to rest. The nose is the fixed point, so
/// moving the arms or the whole body never counts. One rep credits both sides.
final class DumbbellShrugAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: DumbbellShrugConfiguration
    private var tracker: HysteresisPhaseTracker
    private var cycle: Cycle = .awaitingStart
    private var lastCompleteSample: TimeInterval?
    private var recentWidths: [CGFloat] = []
    private var smoothedWidth: CGFloat?
    private var smoothedGaps: [BodySide: CGFloat] = [:]
    private var smoothedLineAnchor: CGPoint?
    private var lockedReference: Reference?
    private var awayFromRestSince: TimeInterval?
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: DumbbellShrugFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedTop: Bool)
    }

    /// Each shoulder's resting nose-to-shoulder gap as a fraction of current shoulder width, plus the line ruler.
    private struct Reference {
        var restRatios: [BodySide: Double]
        var width: CGFloat

        var restRatio: Double {
            BodySide.allCases.compactMap { restRatios[$0] }.reduce(0, +) / Double(BodySide.allCases.count)
        }
    }

    init(epoch: Int, configuration: DumbbellShrugConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = DumbbellShrugFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        let confidence = configuration.minimumJointConfidence
        guard let nose = frame.point(.nose, minimumConfidence: confidence),
              let leftShoulder = frame.point(.leftShoulder, minimumConfidence: confidence),
              let rightShoulder = frame.point(.rightShoulder, minimumConfidence: confidence),
              ArmGeometry.distance(leftShoulder, rightShoulder) > 1 else {
            var analysis = ExerciseAnalysis()
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }

        let time = frame.timestamp
        if let lastCompleteSample, time - lastCompleteSample > configuration.maximumSampleGap {
            invalidateCycleAndReferences()
        }
        if referenceExpired(at: time) {
            invalidateCycleAndReferences()
        }
        lastCompleteSample = time

        let shoulders: [BodySide: CGPoint] = [.left: leftShoulder, .right: rightShoulder]
        let shoulderMidpoint = ArmGeometry.midpoint(leftShoulder, rightShoulder)
        let live = liveReference(nose: nose, left: leftShoulder, right: rightShoulder)
        let reference = lockedReference ?? live
        let currentWidth = smoothedWidth ?? live.width
        var sideLifts: [BodySide: Double] = [:]
        for side in BodySide.allCases {
            guard let shoulder = shoulders[side] else { continue }
            sideLifts[side] = (reference.restRatios[side] ?? 0) - Double((shoulder.y - nose.y) / currentWidth)
        }
        let lift = sideLifts.values.reduce(0, +) / Double(max(sideLifts.count, 1))
        let zone = classify(lift)
        let newlyConfirmed = tracker.update(zone)
        let atRest = tracker.confirmed == .bottom && zone == .bottom
        updateLock(atRest: atRest, live: live, at: time)

        var analysis = ExerciseAnalysis()
        let arms = BodySide.allCases.compactMap { side in
            ArmGeometry.arm(side, in: frame, minimumConfidence: confidence).map { (side, $0) }
        }
        for (side, arm) in arms {
            analysis.readings[side] = ArmReading(signal: sideLifts[side] ?? lift, elbowAngle: arm.elbowAngle, zone: zone)
        }
        let armsHanging = arms.count == BodySide.allCases.count && arms.allSatisfy { _, arm in
            arm.elbowAngle >= configuration.minimumHangingElbowAngle
                && arm.wrist.y - arm.shoulder.y >= configuration.minimumHangingArmDrop * arm.armLength
        }
        analysis.startPositionHeld = atRest && armsHanging
        analysis.endPositionSides = tracker.confirmed == .top ? Set(BodySide.allCases) : []
        lastThresholds = [.left: thresholds(nose: nose, shoulderMidpoint: shoulderMidpoint, live: live)]
        analysis.thresholds = lastThresholds

        let formJoints: Set<LandmarkType> = Set(BodySide.allCases.flatMap { $0.armJoints + [$0.hip] }).union([.nose])
        if !frame.estimatedJoints.isDisjoint(with: formJoints) {
            // Counting can use a completed pose, but form checks must not trust estimated joints.
            formMonitor.invalidate()
            analysis.formReadings = formMonitor.readings
        } else {
            let elbowAngle = arms.count == BodySide.allCases.count ? arms.map(\.1.elbowAngle).min() : nil
            let form = formMonitor.update(
                at: time,
                sample: .init(lift: lift, sideLifts: sideLifts, lowestElbowAngle: elbowAngle,
                              torsoOffset: torsoOffset(frame, shoulderMidpoint: shoulderMidpoint,
                                                       width: reference.width)),
                zone: zone,
                confirmed: tracker.confirmed,
                counting: counting
            )
            analysis.repForms = form.repForms
            analysis.formSignals = form.signals
            analysis.formReadings = formMonitor.readings
        }

        guard counting else {
            cycle = .awaitingStart
            return analysis
        }

        switch cycle {
        case .awaitingStart:
            if atRest { cycle = .active(movementStart: time, reachedTop: false) }
        case .active(var movementStart, var reachedTop):
            if !reachedTop, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedTop = true }
            if newlyConfirmed == .bottom {
                if reachedTop, time - movementStart >= configuration.minimumRepDuration {
                    // Both shoulders move together, so the rep counts for both sides.
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                }
                movementStart = time
                reachedTop = false
            }
            cycle = .active(movementStart: movementStart, reachedTop: reachedTop)
        }
        return analysis
    }

    // MARK: - References and thresholds

    /// Smoothed resting gaps use current shoulder width; the widest recent span remains the threshold-line ruler.
    private func liveReference(nose: CGPoint, left: CGPoint, right: CGPoint) -> Reference {
        let measuredWidth = ArmGeometry.distance(left, right)
        recentWidths.append(measuredWidth)
        if recentWidths.count > configuration.rulerWindow {
            recentWidths.removeFirst(recentWidths.count - configuration.rulerWindow)
        }
        let width = max(recentWidths.max() ?? 1, 1)
        let previousWidth = smoothedWidth ?? measuredWidth
        let currentWidth = previousWidth + (measuredWidth - previousWidth) * configuration.gapSmoothing
        smoothedWidth = currentWidth
        var ratios: [BodySide: Double] = [:]
        for (side, shoulder) in [(BodySide.left, left), (.right, right)] {
            let gap = shoulder.y - nose.y
            let previous = smoothedGaps[side] ?? gap
            let smoothed = previous + (gap - previous) * configuration.gapSmoothing
            smoothedGaps[side] = smoothed
            ratios[side] = Double(smoothed / max(currentWidth, 1))
        }
        return Reference(restRatios: ratios, width: width)
    }

    /// While resting, the ruler follows the user's distance from the phone, but the rest gap moves only toward a
    /// clearly lower rest. A return that stops just inside the Rest line therefore never ratchets the lines up.
    private func updateLock(atRest: Bool, live: Reference, at time: TimeInterval) {
        if atRest {
            awayFromRestSince = nil
            guard let locked = lockedReference else {
                lockedReference = live
                return
            }
            let ratios = live.restRatio >= locked.restRatio + configuration.restRefreshDepth
                ? live.restRatios : locked.restRatios
            lockedReference = Reference(restRatios: ratios, width: live.width)
            return
        }
        guard lockedReference != nil else { return }
        let since = awayFromRestSince ?? time
        awayFromRestSince = since
    }

    /// A timed-out reference ends the active cycle before this sample is used to acquire a new one.
    private func referenceExpired(at time: TimeInterval) -> Bool {
        guard lockedReference != nil, let awayFromRestSince else { return false }
        return time - awayFromRestSince > configuration.referenceTimeout
    }

    /// One segment across both shoulders at each threshold, measured down from the smoothed nose like the signal.
    private func thresholds(nose: CGPoint, shoulderMidpoint: CGPoint, live: Reference) -> ArmThresholds {
        let previous = smoothedLineAnchor ?? CGPoint(x: shoulderMidpoint.x, y: nose.y)
        let anchor = CGPoint(x: previous.x + (shoulderMidpoint.x - previous.x) * configuration.gapSmoothing,
                             y: previous.y + (nose.y - previous.y) * configuration.gapSmoothing)
        smoothedLineAnchor = anchor
        let reference = lockedReference ?? live
        func line(lift: Double, label: String) -> ThresholdLine {
            let y = anchor.y + CGFloat(reference.restRatio - lift) * reference.width
            let halfWidth = 0.6 * reference.width
            return ThresholdLine(from: CGPoint(x: anchor.x - halfWidth, y: y),
                                 to: CGPoint(x: anchor.x + halfWidth, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(lift: configuration.restMaximumLift, label: "Rest ↓"),
                             topLine: line(lift: configuration.topMinimumLift, label: "Top ↑"),
                             isLocked: lockedReference != nil, confirmed: confirmed)
    }

    /// Sideways shoulder-midpoint offset from the hip midpoint, in shoulder widths; nil without both hips.
    private func torsoOffset(_ frame: PoseFrame, shoulderMidpoint: CGPoint, width: CGFloat) -> Double? {
        let confidence = configuration.minimumJointConfidence
        guard let leftHip = frame.point(.leftHip, minimumConfidence: confidence),
              let rightHip = frame.point(.rightHip, minimumConfidence: confidence),
              width > 1 else { return nil }
        return Double((shoulderMidpoint.x - ArmGeometry.midpoint(leftHip, rightHip).x) / width)
    }

    // MARK: - Counting

    private func classify(_ lift: Double) -> MovementZone {
        let tolerance = 1e-9
        if lift <= configuration.restMaximumLift + tolerance { return .bottom }
        if lift >= configuration.topMinimumLift - tolerance { return .top }
        return .middle
    }

    /// A gap can come with a new position or distance, so the rest reference and ruler are measured afresh.
    private func invalidateCycleAndReferences() {
        cycle = .awaitingStart
        tracker.reset()
        formMonitor.invalidate()
        recentWidths = []
        smoothedWidth = nil
        smoothedGaps = [:]
        smoothedLineAnchor = nil
        lockedReference = nil
        awayFromRestSince = nil
        lastThresholds = [:]
    }
}

/// Observes each shrug for height, evenness, straight arms, and a still torso. Counting never depends on it.
struct DumbbellShrugFormMonitor {
    struct Sample {
        /// Shoulder-midpoint lift above the locked rest, in shoulder widths.
        let lift: Double
        let sideLifts: [BodySide: Double]
        /// The more bent elbow; nil unless both arms are visible.
        let lowestElbowAngle: Double?
        let torsoOffset: Double?
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct Attempt {
        var peakLift: Double
        /// Left minus right rise, read at the peak sample.
        var sideDifferenceAtPeak: Double
        var reachedTop = false
    }

    private struct Summary {
        var peakLift: Double
        var sideDifference: Double
    }

    private let configuration: DumbbellShrugConfiguration
    private var attempt: Attempt?
    private var hasSettled = false
    private var torsoBaseline: [Double] = []
    private var torsoDeviation: Double?
    private var lastElbowAngle: Double?
    private var lastSummary: Summary?

    init(configuration: DumbbellShrugConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, sample: Sample, zone: MovementZone, confirmed: MovementZone?,
                         counting: Bool) -> Output {
        var output = Output()
        let settled = zone == .bottom && confirmed == .bottom
        updateTorso(sample.torsoOffset, settled: settled)
        lastElbowAngle = sample.lowestElbowAngle
        guard counting else {
            // A paused or not-yet-started set must settle at rest again before the next attempt.
            attempt = nil
            hasSettled = false
            return output
        }

        if let torsoDeviation, abs(torsoDeviation) > configuration.torsoOffsetTolerance {
            output.signals.insert(.shrugTorso)
        }
        if sample.lift >= configuration.attemptMinimumLift, let elbow = sample.lowestElbowAngle,
           elbow < configuration.minimumElbowAngle {
            output.signals.insert(.shrugArmsStraight)
        }

        if settled {
            if let attempt { output.repForms.append(finish(attempt, at: time)) }
            attempt = nil
            hasSettled = true
            return output
        }
        guard hasSettled else { return output }

        if var active = attempt {
            if sample.lift > active.peakLift {
                active.peakLift = sample.lift
                active.sideDifferenceAtPeak = sideDifference(sample)
            }
            if confirmed == .top { active.reachedTop = true }
            attempt = active
        } else if sample.lift >= configuration.attemptMinimumLift {
            attempt = Attempt(peakLift: sample.lift, sideDifferenceAtPeak: sideDifference(sample),
                              reachedTop: confirmed == .top)
        }
        return output
    }

    mutating func invalidate() {
        attempt = nil
        hasSettled = false
        lastElbowAngle = nil
    }

    var readings: [FormReading] {
        func format(_ value: Double?, _ pattern: String) -> String {
            value.map { String(format: pattern, $0) } ?? "–"
        }
        return [
            FormReading(label: "lift", value: format(lastSummary?.peakLift, "%.2f")),
            FormReading(label: "Δh", value: format(lastSummary.map { abs($0.sideDifference) }, "%.2f")),
            FormReading(label: "elbow", value: format(lastElbowAngle, "%.0f°")),
            FormReading(label: "torso", value: format(torsoDeviation.map(abs), "%.2f"))
        ]
    }

    private func sideDifference(_ sample: Sample) -> Double {
        (sample.sideLifts[.left] ?? sample.lift) - (sample.sideLifts[.right] ?? sample.lift)
    }

    private mutating func finish(_ attempt: Attempt, at time: TimeInterval) -> RepForm {
        var flags: Set<CoachingCueID> = []
        if !attempt.reachedTop { flags.insert(.shrugHigher) }
        if abs(attempt.sideDifferenceAtPeak) > configuration.maximumSideDifference { flags.insert(.shrugEven) }
        lastSummary = Summary(peakLift: attempt.peakLift, sideDifference: attempt.sideDifferenceAtPeak)
        return RepForm(timestamp: time, flags: flags)
    }

    private mutating func updateTorso(_ offset: Double?, settled: Bool) {
        guard let offset else {
            torsoDeviation = nil
            return
        }
        if settled, torsoBaseline.count < configuration.baselineSamples {
            torsoBaseline.append(offset)
        }
        guard torsoBaseline.count >= configuration.baselineSamples else {
            torsoDeviation = nil
            return
        }
        torsoDeviation = offset - torsoBaseline.reduce(0, +) / Double(torsoBaseline.count)
    }
}
