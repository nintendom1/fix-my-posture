import CoreGraphics
import Foundation

/// Counts two-arm presses from the front: both arms must reach the top within one cycle and
/// both must return to the start. Each arm has its own hysteresis tracker.
///
/// Heights are measured in that arm's own length, so the rule is the same at any distance and for
/// any body proportions, and it never needs the hips. When an arm confirms the start position, its
/// shoulder height and ruler are locked until it comes back, so the thresholds don't drift as the
/// shoulders lift during the press.
final class ShoulderPressAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: ShoulderPressConfiguration
    private var trackers: [BodySide: HysteresisPhaseTracker]
    private var cycle: Cycle = .awaitingBottom
    private var lastCompleteSample: TimeInterval?
    private var recentArmLengths: [BodySide: [CGFloat]] = [:]
    private var smoothedShoulderY: [BodySide: CGFloat] = [:]
    private var lockedReference: [BodySide: Reference] = [:]
    private var awayFromStartSince: [BodySide: TimeInterval] = [:]
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: ShoulderPressFormMonitor

    private enum Cycle {
        /// Both arms must confirm the start before a rep can begin.
        case awaitingBottom
        case active(ActiveCycle)
    }

    private struct ActiveCycle {
        /// Last time both arms sat at the start before any arm reached the top.
        var movementStart: TimeInterval
        var reachedTop: Set<BodySide> = []
    }

    /// The shoulder height and arm length that one arm's heights are measured from.
    private struct Reference {
        var shoulderY: CGFloat
        var ruler: CGFloat
    }

    init(epoch: Int, configuration: ShoulderPressConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        let tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        trackers = [.left: tracker, .right: tracker]
        formMonitor = ShoulderPressFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        let confidence = configuration.minimumJointConfidence
        guard let left = ArmGeometry.arm(.left, in: frame, minimumConfidence: confidence),
              let right = ArmGeometry.arm(.right, in: frame, minimumConfidence: confidence) else {
            // Trackers and references hold; the gap check below decides whether the cycle survives.
            var analysis = ExerciseAnalysis()
            analysis.startPositionHeld = bothConfirmedBottom
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }

        let time = frame.timestamp
        var rejections: [RepRejection] = []
        if let last = lastCompleteSample, time - last > configuration.maximumSampleGap {
            if case .active(let active) = cycle, let lost = RepRejection.lost(at: time, .trackingGap(
                seconds: time - last, maximum: configuration.maximumSampleGap,
                stage: .of(reachedEnd: !active.reachedTop.isEmpty,
                           zones: BodySide.allCases.map { trackers[$0]?.lastZone ?? .bottom }))) {
                rejections.append(lost)
            }
            invalidateCycle()
        }
        lastCompleteSample = time

        var analysis = ExerciseAnalysis()
        analysis.rejections = rejections
        var zones: [BodySide: MovementZone] = [:]
        var newlyConfirmed: [BodySide: MovementZone] = [:]
        var formSamples: [BodySide: ShoulderPressFormMonitor.ArmSample] = [:]
        var rulers: [CGFloat] = []
        for (side, arm, other) in [(BodySide.left, left, right), (.right, right, left)] {
            let live = liveReference(for: side, arm: arm)
            let reference = lockedReference[side] ?? live
            let height = Double((reference.shoulderY - arm.wrist.y) / reference.ruler)
            let elbowAngle = arm.elbowAngle
            let zone = classify(height: height, elbowAngle: elbowAngle, forearmPointsUp: arm.wrist.y < arm.elbow.y)
            zones[side] = zone
            analysis.readings[side] = ArmReading(signal: height, elbowAngle: elbowAngle, zone: zone)
            if let confirmed = trackers[side]?.update(zone) { newlyConfirmed[side] = confirmed }
            formSamples[side] = .init(height: height, elbowAngle: elbowAngle, zone: zone, confirmed: trackers[side]?.confirmed)
            rulers.append(reference.ruler)
            updateLock(for: side, zone: zone, live: live, at: time)
            analysis.thresholds[side] = thresholds(for: side, shoulderX: arm.shoulder.x, otherShoulderX: other.shoulder.x, live: live)
        }
        lastThresholds = analysis.thresholds

        analysis.endPositionSides = Set(BodySide.allCases.filter { trackers[$0]?.confirmed == .top })
        analysis.startPositionHeld = bothConfirmedBottom

        if !frame.estimatedJoints.isDisjoint(with: Set(BodySide.allCases.flatMap(\.armJoints))) {
            formMonitor.invalidate()
        }
        let form = formMonitor.update(at: time, arms: formSamples,
                                      torsoOffset: torsoOffset(frame, left: left, right: right, rulers: rulers),
                                      counting: counting)
        analysis.repForms = form.repForms
        analysis.formSignals = form.signals
        analysis.formReadings = formMonitor.readings

        guard counting else {
            if case .active(let active) = cycle, let lost = RepRejection.lost(at: time, .countingStopped(
                stage: .of(reachedEnd: !active.reachedTop.isEmpty, zones: zones.values))) {
                analysis.rejections.append(lost)
            }
            cycle = .awaitingBottom
            return analysis
        }

        switch cycle {
        case .awaitingBottom:
            if bothConfirmedBottom { cycle = .active(ActiveCycle(movementStart: time)) }
        case .active(var active):
            if active.reachedTop.isEmpty, zones.values.allSatisfy({ $0 == .bottom }) {
                active.movementStart = time
            }
            for (side, zone) in newlyConfirmed where zone == .top {
                active.reachedTop.insert(side)
            }
            if !active.reachedTop.isEmpty, bothConfirmedBottom {
                let duration = time - active.movementStart
                if active.reachedTop.count < BodySide.allCases.count {
                    analysis.rejections.append(RepRejection(timestamp: time, reason: .partialEnd(reached: active.reachedTop)))
                } else if duration >= configuration.minimumRepDuration {
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                } else {
                    analysis.rejections.append(RepRejection(timestamp: time, reason: .tooFast(
                        duration: duration, minimum: configuration.minimumRepDuration)))
                }
                active = ActiveCycle(movementStart: time)
            }
            cycle = .active(active)
        }
        return analysis
    }

    // MARK: - References

    /// Smoothed shoulder height and the longest recent arm length. A maximum resists momentary
    /// foreshortening when an arm points toward the camera.
    private func liveReference(for side: BodySide, arm: ArmPoints) -> Reference {
        var lengths = recentArmLengths[side] ?? []
        lengths.append(arm.armLength)
        if lengths.count > configuration.rulerWindow { lengths.removeFirst(lengths.count - configuration.rulerWindow) }
        recentArmLengths[side] = lengths

        let previous = smoothedShoulderY[side] ?? arm.shoulder.y
        let shoulderY = previous + (arm.shoulder.y - previous) * configuration.shoulderSmoothing
        smoothedShoulderY[side] = shoulderY
        return Reference(shoulderY: shoulderY, ruler: max(lengths.max() ?? arm.armLength, 1))
    }

    /// Refreshes the lock while the arm sits at the start; holds it while the arm is away. A lock held
    /// too long (for example after stepping closer mid-rep) is dropped so the arm can't get stuck.
    private func updateLock(for side: BodySide, zone: MovementZone, live: Reference, at time: TimeInterval) {
        if trackers[side]?.confirmed == .bottom, zone == .bottom {
            lockedReference[side] = live
            awayFromStartSince[side] = nil
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

    /// Each line spans from just inside the shoulder to past the elbow: where the wrist travels.
    private func thresholds(for side: BodySide, shoulderX: CGFloat, otherShoulderX: CGFloat, live: Reference) -> ArmThresholds {
        let reference = lockedReference[side] ?? live
        let outward: CGFloat = shoulderX >= otherShoulderX ? 1 : -1
        func line(heightAbove height: Double, label: String) -> ThresholdLine {
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
            startLine: line(heightAbove: configuration.bottomMaxHeight, label: "Start ↓"),
            topLine: line(heightAbove: configuration.topMinHeight, label: "Top ↑"),
            isLocked: lockedReference[side] != nil,
            confirmed: confirmed
        )
    }

    /// Sideways offset of the shoulder midpoint from the hip midpoint, in arm lengths; nil without hips.
    private func torsoOffset(_ frame: PoseFrame, left: ArmPoints, right: ArmPoints, rulers: [CGFloat]) -> Double? {
        let confidence = configuration.minimumJointConfidence
        guard let leftHip = frame.point(.leftHip, minimumConfidence: confidence),
              let rightHip = frame.point(.rightHip, minimumConfidence: confidence),
              !rulers.isEmpty else { return nil }
        let ruler = rulers.reduce(0, +) / CGFloat(rulers.count)
        let shoulders = ArmGeometry.midpoint(left.shoulder, right.shoulder)
        let hips = ArmGeometry.midpoint(leftHip, rightHip)
        return Double((shoulders.x - hips.x) / ruler)
    }

    // MARK: - Classification

    private var bothConfirmedBottom: Bool {
        BodySide.allCases.allSatisfy { trackers[$0]?.confirmed == .bottom }
    }

    private func classify(height: Double, elbowAngle: Double, forearmPointsUp: Bool) -> MovementZone {
        if height <= configuration.bottomMaxHeight, elbowAngle <= configuration.bottomMaxElbowAngle, forearmPointsUp {
            return .bottom
        }
        if height >= configuration.topMinHeight, elbowAngle >= configuration.topMinElbowAngle {
            return .top
        }
        return .middle
    }

    private func invalidateCycle() {
        cycle = .awaitingBottom
        formMonitor.invalidate()
        for side in BodySide.allCases { trackers[side]?.reset() }
        lockedReference = [:]
        awayFromStartSince = [:]
    }
}
