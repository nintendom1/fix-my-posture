import CoreGraphics
import Foundation

/// Counts a wall push-up from the arm nearest the phone: straight arms are Up, bent elbows near the wall are
/// Down, and returning to Up completes one rep. The chosen arm stays fixed through brief occlusions; after a tracking
/// gap (the user turned around, or that arm left the frame) the analyzer resets and picks the visible arm again.
final class WallPushUpAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: WallPushUpConfiguration
    private var tracker: HysteresisPhaseTracker
    private var trackedSide: BodySide?
    private var lastSample: TimeInterval?
    private var recentArmLengths: [(time: TimeInterval, length: CGFloat)] = []
    private var lockedRuler: CGFloat?
    private var awayFromStartSince: TimeInterval?
    private var cycle: Cycle = .awaitingStart
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor = WallPushUpFormMonitor()

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedDown: Bool)
    }

    init(epoch: Int, configuration: WallPushUpConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        guard let selection = selectArm(in: frame) else {
            analysis.startPositionHeld = false
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }
        let (side, arm) = selection
        let time = frame.timestamp

        if let lastSample, time - lastSample > configuration.maximumSampleGap {
            let gap = time - lastSample
            if case .active(_, let reachedDown) = cycle,
               let lost = RepRejection.lost(at: time, .trackingGap(
                seconds: gap, maximum: configuration.maximumSampleGap,
                stage: .of(reachedEnd: reachedDown, zones: [tracker.lastZone ?? .bottom]))) {
                analysis.rejections.append(lost)
            }
            resetTracking(clearRuler: true)
        }
        lastSample = time

        let ruler = liveRuler(for: arm, at: time)
        let referenceRuler = max(lockedRuler ?? ruler, 1)
        let horizontalRatio = Double(abs(arm.wrist.x - arm.shoulder.x) / referenceRuler)
        let zone = classify(horizontalRatio: horizontalRatio, elbowAngle: arm.elbowAngle)
        let newlyConfirmed = tracker.update(zone)
        let expired = updateLock(zone: zone, horizontalRatio: horizontalRatio, elbowAngle: arm.elbowAngle,
                                 liveRuler: ruler, at: time)
        if let pendingRejection {
            analysis.rejections.append(pendingRejection)
            self.pendingRejection = nil
        }

        analysis.readings[side] = ArmReading(signal: horizontalRatio, elbowAngle: arm.elbowAngle, zone: zone)
        lastThresholds = [side: makeThresholds(arm: arm, ruler: referenceRuler)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? [side] : []
        analysis.startPositionHeld = tracker.confirmed == .bottom && zone == .bottom

        if expired {
            analysis.startPositionHeld = false
            analysis.endPositionSides = []
            analysis.formReadings = formMonitor.readings
            return analysis
        }

        let formJoints = Set(side.armJoints + [side.hip, side.ankle])
        if !frame.estimatedJoints.isDisjoint(with: formJoints) {
            formMonitor.invalidate()
        } else {
            let bodyLineBend = bodyLineBend(for: side, in: frame)
            analysis.repForms = formMonitor.update(
                at: time,
                horizontalRatio: horizontalRatio,
                bodyLineBend: bodyLineBend,
                zone: zone,
                newlyConfirmed: newlyConfirmed,
                confirmed: tracker.confirmed,
                counting: counting,
                configuration: configuration
            )
        }
        analysis.formReadings = formMonitor.readings

        guard counting else {
            if case .active(_, let reachedDown) = cycle,
               let lost = RepRejection.lost(at: time, .countingStopped(
                stage: .of(reachedEnd: reachedDown, zones: [zone]))) {
                analysis.rejections.append(lost)
            }
            cycle = .awaitingStart
            return analysis
        }

        switch cycle {
        case .awaitingStart:
            if tracker.confirmed == .bottom {
                cycle = .active(movementStart: time, reachedDown: false)
            }
        case .active(var movementStart, var reachedDown):
            if !reachedDown, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedDown = true }
            if newlyConfirmed == .bottom {
                if reachedDown, time - movementStart >= configuration.minimumRepDuration {
                    // This is one whole-body movement, so the session's left/right minimum can advance.
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                } else if reachedDown {
                    analysis.rejections.append(RepRejection(timestamp: time, reason: .tooFast(
                        duration: time - movementStart, minimum: configuration.minimumRepDuration)))
                }
                movementStart = time
                reachedDown = false
            }
            cycle = .active(movementStart: movementStart, reachedDown: reachedDown)
        }
        return analysis
    }

    private func selectArm(in frame: PoseFrame) -> (BodySide, ArmPoints)? {
        if let trackedSide {
            if let arm = ArmGeometry.arm(trackedSide, in: frame,
                                         minimumConfidence: configuration.minimumJointConfidence) {
                return (trackedSide, arm)
            }
            // Keep the arm through a brief occlusion. Once it has been gone longer than a tracking gap, `process`
            // resets everything for this frame, so choosing the visible arm afresh carries nothing over.
            guard let lastSample, frame.timestamp - lastSample > configuration.maximumSampleGap else { return nil }
            self.trackedSide = nil
        }
        let candidate = BodySide.allCases.compactMap { side -> (BodySide, ArmPoints, Double)? in
            guard let arm = ArmGeometry.arm(side, in: frame,
                                            minimumConfidence: configuration.minimumJointConfidence) else { return nil }
            let confidence = side.armJoints.compactMap { frame.pose[$0]?.confidence }.reduce(0, +)
            return (side, arm, confidence)
        }.max { $0.2 < $1.2 }
        guard let candidate else { return nil }
        trackedSide = candidate.0
        return (candidate.0, candidate.1)
    }

    private func classify(horizontalRatio: Double, elbowAngle: Double) -> MovementZone {
        if horizontalRatio >= configuration.upMinHorizontalRatio,
           elbowAngle >= configuration.upMinElbowAngle { return .bottom }
        if horizontalRatio <= configuration.downMaxHorizontalRatio,
           elbowAngle <= configuration.downMaxElbowAngle { return .top }
        return .middle
    }

    private func liveRuler(for arm: ArmPoints, at time: TimeInterval) -> CGFloat {
        recentArmLengths.append((time, arm.armLength))
        recentArmLengths.removeAll { time - $0.time > configuration.rulerWindow }
        return max(recentArmLengths.map(\.length).max() ?? arm.armLength, 1)
    }

    /// Lock the first confirmed Up. Later refreshes require a more complete return than the Up threshold, so a
    /// return that just clears the line cannot ratchet the ruler toward the wall.
    private func updateLock(zone: MovementZone, horizontalRatio: Double, elbowAngle: Double,
                            liveRuler: CGFloat, at time: TimeInterval) -> Bool {
        if tracker.confirmed == .bottom, zone == .bottom {
            // The first confirmed Up may sit on the line. Later refreshes require a true, straight-arm rest.
            let trueRest = horizontalRatio >= configuration.referenceRefreshMinHorizontalRatio
                && elbowAngle >= configuration.referenceRefreshMinElbowAngle
            if lockedRuler == nil || trueRest {
                lockedRuler = liveRuler
            }
            awayFromStartSince = nil
            return false
        }
        guard lockedRuler != nil else { return false }
        let since = awayFromStartSince ?? time
        awayFromStartSince = since
        guard time - since > configuration.referenceTimeout else { return false }

        if case .active(_, let reachedDown) = cycle,
           let lost = RepRejection.lost(at: time, .referenceExpired(
            stage: .of(reachedEnd: reachedDown, zones: [tracker.lastZone ?? zone]))) {
            // Stored on the next output frame by process through this pending rejection.
            pendingRejection = lost
        }
        resetTracking(clearRuler: true)
        return true
    }

    private var pendingRejection: RepRejection?

    private func makeThresholds(arm: ArmPoints, ruler: CGFloat) -> ArmThresholds {
        let facing: CGFloat = arm.wrist.x >= arm.shoulder.x ? 1 : -1
        func line(ratio: Double, label: String) -> ThresholdLine {
            let shoulderX = arm.wrist.x - facing * CGFloat(ratio) * ruler
            let halfHeight = max(8, ruler * 0.14)
            return ThresholdLine(from: CGPoint(x: shoulderX, y: arm.shoulder.y - halfHeight),
                                 to: CGPoint(x: shoulderX, y: arm.shoulder.y + halfHeight), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        let downLabel = configuration.shallow ? "Bend a little ↓" : "Down ↓"
        return ArmThresholds(startLine: line(ratio: configuration.upMinHorizontalRatio, label: "Up ↑"),
                             topLine: line(ratio: configuration.downMaxHorizontalRatio, label: downLabel),
                             isLocked: lockedRuler != nil, confirmed: confirmed)
    }

    private func bodyLineBend(for side: BodySide, in frame: PoseFrame) -> Double? {
        guard let shoulder = frame.point(side.shoulder, minimumConfidence: configuration.minimumJointConfidence),
              let hip = frame.point(side.hip, minimumConfidence: configuration.minimumJointConfidence),
              let ankle = frame.point(side.ankle, minimumConfidence: configuration.minimumJointConfidence) else { return nil }
        return 180 - ArmGeometry.angle(at: hip, shoulder, ankle)
    }

    private func resetTracking(clearRuler: Bool) {
        tracker.reset()
        cycle = .awaitingStart
        lockedRuler = nil
        awayFromStartSince = nil
        formMonitor.invalidate()
        if clearRuler {
            recentArmLengths.removeAll()
            lastThresholds = [:]
        }
    }
}

/// Evaluates wall-push-up form independently from the rep tracker. An attempt starts at a confirmed Up and only
/// counts once the arm has left Up for two samples in a row. It ends on the first sample back at Up: one frame
/// before the tracker confirms Up and counts the rep, so its form reaches the set even when that rep completes it.
/// Down is the tracker's confirmed Down, so one noisy sample neither satisfies depth nor starts a lockout check. The
/// body-line value is captured only at the deepest sample, and estimates invalidate this state without interrupting
/// counting.
struct WallPushUpFormMonitor {
    private struct Attempt {
        /// Left Up for `confirmationSamples` samples in a row, so one noisy sample at rest isn't an attempt.
        var started = false
        var awayFromUpSamples = 0
        var reachedDown = false
        /// Came back at least halfway toward Up after Down, so another Down is a new descent.
        var roseFromDown = false
        var downAgainSamples = 0
        var deepestRatio = Double.infinity
        var bodyLineBendAtDeepest: Double?
    }

    private var attempt: Attempt?
    private var lastDepth: Double?
    private var lastBodyLine: Double?

    mutating func update(at time: TimeInterval, horizontalRatio: Double, bodyLineBend: Double?, zone: MovementZone,
                         newlyConfirmed: MovementZone?, confirmed: MovementZone?, counting: Bool,
                         configuration: WallPushUpConfiguration) -> [RepForm] {
        guard counting else {
            attempt = nil
            return []
        }
        guard var current = attempt else {
            if confirmed == .bottom { attempt = Attempt() }
            return []
        }
        let halfway = (configuration.upMinHorizontalRatio + configuration.downMaxHorizontalRatio) / 2
        current.awayFromUpSamples = zone == .bottom ? 0 : current.awayFromUpSamples + 1
        if current.awayFromUpSamples >= configuration.confirmationSamples { current.started = true }
        if current.started, horizontalRatio < current.deepestRatio {
            current.deepestRatio = horizontalRatio
            current.bodyLineBendAtDeepest = bodyLineBend
        }

        if zone == .bottom {
            guard current.started else {
                attempt = current
                return []
            }
            var flags = Set<CoachingCueID>()
            if !current.reachedDown {
                flags.insert(.wallPushUpDeeper)
            } else if let bend = current.bodyLineBendAtDeepest, bend > configuration.bodyLineMaximumBend {
                flags.insert(.wallPushUpBodyLine)
            }
            lastDepth = current.deepestRatio
            lastBodyLine = current.bodyLineBendAtDeepest
            attempt = Attempt()
            return [RepForm(timestamp: time, flags: flags)]
        }

        if newlyConfirmed == .top { current.reachedDown = true }
        var forms: [RepForm] = []
        if current.reachedDown {
            if horizontalRatio >= halfway {
                current.roseFromDown = true
                current.downAgainSamples = 0
            } else if current.roseFromDown, zone == .top {
                current.downAgainSamples += 1
                if current.downAgainSamples >= configuration.confirmationSamples {
                    // Back down without pressing to Up: flag it, and treat this descent as a new attempt at Down.
                    forms.append(RepForm(timestamp: time, flags: [.wallPushUpLockout]))
                    lastDepth = current.deepestRatio
                    lastBodyLine = current.bodyLineBendAtDeepest
                    current = Attempt(started: true, reachedDown: true, deepestRatio: horizontalRatio,
                                      bodyLineBendAtDeepest: bodyLineBend)
                }
            } else {
                current.downAgainSamples = 0
            }
        }
        attempt = current
        return forms
    }

    mutating func invalidate() {
        attempt = nil
    }

    var readings: [FormReading] {
        [
            FormReading(label: "deepest h", value: lastDepth.map { String(format: "%.2f", $0) } ?? "–"),
            FormReading(label: "body bend", value: lastBodyLine.map { String(format: "%.0f°", $0) } ?? "–")
        ]
    }
}
