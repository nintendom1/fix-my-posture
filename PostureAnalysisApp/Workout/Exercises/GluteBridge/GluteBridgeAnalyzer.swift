import CoreGraphics
import Foundation

/// Counts one side-view bridge from Down to Up. Angles use pixel-space joints and do not depend on scale.
final class GluteBridgeAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: GluteBridgeConfiguration
    private var nearSide = GluteBridgeNearSideSelector()
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var lockedReference: Reference?
    private var cycle = Cycle.awaitingStart
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: GluteBridgeFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedUp: Bool)
    }

    /// Threshold lines stay on the first true Down position. A deeper, settled Down may refresh them.
    private struct Reference {
        let shoulder: CGPoint
        let knee: CGPoint
        let hip: CGPoint
        let thighLength: CGFloat
        let facing: CGFloat
        let downAngle: Double
    }

    init(epoch: Int, configuration: GluteBridgeConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = GluteBridgeFormMonitor(configuration: configuration)
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

        let angle = Self.hipAngle(shoulder: body.shoulder, hip: body.hip, knee: body.knee,
                                  facing: body.facing)
        let zone = classify(angle)
        let newlyConfirmed = tracker.update(zone)
        let liveReference = makeReference(for: body, downAngle: angle)
        updateReference(zone: zone, live: liveReference)
        let reference = lockedReference ?? liveReference

        lastThresholds = [body.side: makeThresholds(reference: reference)]
        analysis.thresholds = lastThresholds
        analysis.startPositionHeld = tracker.confirmed == .bottom
        analysis.endPositionSides = tracker.confirmed == .top ? Set(BodySide.allCases) : []

        let formJoints: Set<LandmarkType> = [
            .leftShoulder, .rightShoulder, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
        ]
        if !frame.estimatedJoints.isDisjoint(with: formJoints) {
            formMonitor.invalidate()
        } else {
            let kneeAngle = ArmGeometry.angle(at: body.knee, body.hip, body.ankle)
            analysis.repForms = formMonitor.update(
                at: time,
                angle: angle,
                kneeAngle: kneeAngle,
                zone: zone,
                confirmed: tracker.confirmed,
                newlyConfirmed: newlyConfirmed,
                counting: counting
            )
        }
        analysis.formReadings = formMonitor.readings

        guard counting else {
            cycle = .awaitingStart
            return analysis
        }
        switch cycle {
        case .awaitingStart:
            if tracker.confirmed == .bottom {
                cycle = .active(movementStart: time, reachedUp: false)
            }
        case .active(var movementStart, var reachedUp):
            if !reachedUp, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedUp = true }
            if newlyConfirmed == .bottom {
                if reachedUp, time - movementStart >= configuration.minimumRepDuration {
                    // A bridge is a whole-body rep even though Ready tracks one side.
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time,
                                                       sides: Set(BodySide.allCases)))
                }
                movementStart = time
                reachedUp = false
            }
            cycle = .active(movementStart: movementStart, reachedUp: reachedUp)
        }
        return analysis
    }

    private func classify(_ angle: Double) -> MovementZone {
        if angle <= configuration.downMaxAngle + configuration.thresholdAngleTolerance { return .bottom }
        if angle >= configuration.upMinAngle - configuration.thresholdAngleTolerance { return .top }
        return .middle
    }

    private func makeReference(for body: BridgeBodySide, downAngle: Double) -> Reference {
        Reference(shoulder: body.shoulder, knee: body.knee, hip: body.hip,
                  thighLength: max(ArmGeometry.distance(body.hip, body.knee), 1),
                  facing: body.facing, downAngle: downAngle)
    }

    private func updateReference(zone: MovementZone, live: Reference) {
        guard tracker.confirmed == .bottom, zone == .bottom else { return }
        guard let lockedReference else {
            self.lockedReference = live
            return
        }
        guard live.downAngle <= lockedReference.downAngle - configuration.referenceRefreshAngle else { return }
        self.lockedReference = live
    }

    /// Horizontal segments at the hip heights implied by the locked shoulder, knee, and thigh length.
    private func makeThresholds(reference: Reference) -> ArmThresholds {
        func line(angle: Double, label: String) -> ThresholdLine {
            let point = Self.hipPoint(shoulder: reference.shoulder, knee: reference.knee,
                                      thighLength: reference.thighLength,
                                      facing: reference.facing, angle: angle) ?? reference.hip
            let halfWidth = configuration.thresholdHalfWidthThighRatio * reference.thighLength
            return ThresholdLine(from: CGPoint(x: point.x - halfWidth, y: point.y),
                                 to: CGPoint(x: point.x + halfWidth, y: point.y), label: label)
        }

        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(angle: configuration.downMaxAngle, label: "Down ↓"),
                             topLine: line(angle: configuration.upMinAngle, label: "Up ↑"),
                             isLocked: lockedReference != nil, confirmed: confirmed)
    }

    private func resetTracking() {
        tracker.reset()
        cycle = .awaitingStart
        lockedReference = nil
        lastThresholds = [:]
        formMonitor.invalidate()
    }

    /// Uses the interior hip angle on the floor side of the shoulder-knee line and its reflex angle above it.
    static func hipAngle(shoulder: CGPoint, hip: CGPoint, knee: CGPoint, facing: CGFloat) -> Double {
        let interior = ArmGeometry.angle(at: hip, shoulder, knee)
        let lineX = knee.x - shoulder.x
        let lineY = knee.y - shoulder.y
        let hipX = hip.x - shoulder.x
        let hipY = hip.y - shoulder.y
        let signedDistance = (lineX * hipY - lineY * hipX) * facing
        return signedDistance >= 0 ? interior : 360 - interior
    }

    /// Finds the hip with the requested directed angle while preserving the locked hip-to-knee length.
    private static func hipPoint(shoulder: CGPoint, knee: CGPoint, thighLength: CGFloat,
                                 facing: CGFloat, angle: Double) -> CGPoint? {
        let baseLength = ArmGeometry.distance(shoulder, knee)
        guard baseLength > 0, thighLength > 0 else { return nil }
        let minorAngle = angle > 180 ? 360 - angle : angle
        let radians = minorAngle * .pi / 180
        let sine = CGFloat(sin(radians))
        let cosine = CGFloat(cos(radians))
        let radicand = baseLength * baseLength - thighLength * thighLength * sine * sine
        guard radicand >= 0 else { return nil }
        let shoulderHipLength = thighLength * cosine + sqrt(radicand)
        guard shoulderHipLength > 0 else { return nil }
        let along = (thighLength * thighLength + baseLength * baseLength
                     - shoulderHipLength * shoulderHipLength) / (2 * baseLength)
        let acrossSquared = thighLength * thighLength - along * along
        guard acrossSquared >= -0.001 else { return nil }
        let across = sqrt(max(0, acrossSquared))
        let unitX = (shoulder.x - knee.x) / baseLength
        let unitY = (shoulder.y - knee.y) / baseLength
        let perpendicularX = -unitY
        let perpendicularY = unitX
        let positive = CGPoint(x: knee.x + unitX * along + perpendicularX * across,
                               y: knee.y + unitY * along + perpendicularY * across)
        let negative = CGPoint(x: knee.x + unitX * along - perpendicularX * across,
                               y: knee.y + unitY * along - perpendicularY * across)
        let positiveError = abs(Self.hipAngle(shoulder: shoulder, hip: positive, knee: knee,
                                              facing: facing) - angle)
        let negativeError = abs(Self.hipAngle(shoulder: shoulder, hip: negative, knee: knee,
                                              facing: facing) - angle)
        return positiveError <= negativeError ? positive : negative
    }
}

/// The complete shoulder, hip, knee, and ankle set with the strongest confidence. It sticks until the other
/// side is clearly better, so Vision label fluctuations do not change the tracked limb.
private struct GluteBridgeNearSideSelector {
    private(set) var side: BodySide?

    mutating func select(in frame: PoseFrame, minimumConfidence: Double,
                         switchMargin: Double) -> (body: BridgeBodySide, switched: Bool)? {
        let candidates = BodySide.allCases.compactMap { side -> BridgeBodySide? in
            guard let shoulder = frame.point(side.shoulder, minimumConfidence: minimumConfidence),
                  let hip = frame.point(side.hip, minimumConfidence: minimumConfidence),
                  let knee = frame.point(side.knee, minimumConfidence: minimumConfidence),
                  let ankle = frame.point(side.ankle, minimumConfidence: minimumConfidence) else { return nil }
            let confidence = [side.shoulder, side.hip, side.knee, side.ankle]
                .compactMap { frame.pose[$0]?.confidence }.min() ?? 0
            let direction = ankle.x - shoulder.x
            let facing: CGFloat = abs(direction) > 1 ? (direction >= 0 ? 1 : -1) : 1
            return BridgeBodySide(side: side, shoulder: shoulder, hip: hip, knee: knee, ankle: ankle,
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

private struct BridgeBodySide {
    let side: BodySide
    let shoulder: CGPoint
    let hip: CGPoint
    let knee: CGPoint
    let ankle: CGPoint
    let confidence: Double
    let facing: CGFloat
}

/// Tracks one full attempt. Peak-dependent form uses the highest-phi sample and its knee angle.
private struct GluteBridgeFormMonitor {
    private struct Attempt {
        let startAngle: Double
        var peakAngle: Double
        var kneeAngleAtPeak: Double
        var movedFromDown = false
        var reachedUp = false
        var lowestAfterUp: Double?
        var flags: Set<CoachingCueID> = []
    }

    private let configuration: GluteBridgeConfiguration
    private var attempt: Attempt?
    private var lastPeak: Double?
    private var lastKneeAngle: Double?

    init(configuration: GluteBridgeConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, angle: Double, kneeAngle: Double,
                         zone: MovementZone, confirmed: MovementZone?, newlyConfirmed: MovementZone?,
                         counting: Bool) -> [RepForm] {
        guard counting else {
            if attempt == nil, confirmed == .bottom {
                attempt = Attempt(startAngle: angle, peakAngle: angle, kneeAngleAtPeak: kneeAngle)
            }
            return []
        }

        guard var active = attempt else {
            if zone == .bottom {
                attempt = Attempt(startAngle: angle, peakAngle: angle, kneeAngleAtPeak: kneeAngle)
            }
            return []
        }
        if angle > active.peakAngle {
            active.peakAngle = angle
            active.kneeAngleAtPeak = kneeAngle
        }
        if zone != .bottom { active.movedFromDown = true }
        if newlyConfirmed == .top || confirmed == .top { active.reachedUp = true }

        if active.reachedUp,
           active.peakAngle >= configuration.overArchPeakAngle {
            active.flags.insert(.bridgeStraightLine)
        }
        if active.reachedUp,
           active.kneeAngleAtPeak > configuration.feetFarKneeAngle {
            active.flags.insert(.bridgeFeetCloser)
        }
        if active.reachedUp {
            if let lowest = active.lowestAfterUp {
                if angle <= lowest { active.lowestAfterUp = angle }
                if let newLowest = active.lowestAfterUp,
                   active.peakAngle - newLowest >= configuration.lowerAmount,
                   angle - newLowest >= configuration.lowerAmount {
                    active.flags.insert(.bridgeLower)
                }
            } else if active.peakAngle - angle >= configuration.lowerAmount {
                active.lowestAfterUp = angle
            }
        }
        lastPeak = active.peakAngle
        lastKneeAngle = active.kneeAngleAtPeak

        guard active.movedFromDown, zone == .bottom else {
            attempt = active
            return []
        }
        if !active.reachedUp,
           active.peakAngle - active.startAngle >= configuration.attemptMinimumRise {
            active.flags.insert(.bridgeHigher)
        }
        // Report on the first Down sample. The session handles rep completion before same-frame form
        // observations, so this lets the final target rep's form reach the active set.
        attempt = Attempt(startAngle: angle, peakAngle: angle, kneeAngleAtPeak: kneeAngle)
        return [RepForm(timestamp: time, flags: active.flags)]
    }

    mutating func invalidate() {
        attempt = nil
        lastPeak = nil
        lastKneeAngle = nil
    }

    var readings: [FormReading] {
        func value(_ number: Double?) -> String { number.map { String(format: "%.0f°", $0) } ?? "–" }
        return [
            FormReading(label: "Peak φ", value: value(lastPeak)),
            FormReading(label: "Knee at peak", value: value(lastKneeAngle))
        ]
    }
}
