import CoreGraphics
import Foundation

/// Counts overhead triceps extensions from the side using the arm nearer the phone. Both arms move together
/// with one band, so each rep is credited to both sides. A rep is lowered behind the head (Start), straight
/// overhead (Top), and lowered again.
///
/// The elbow height and forearm ruler are locked while the hands are lowered, so the lines hold still.
final class TricepsExtensionAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: TricepsExtensionConfiguration
    private var trackedSide: BodySide?
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var recentForearms: [CGFloat] = []
    private var smoothedElbowY: CGFloat?
    private var locked: Reference?
    private var awayFromStartSince: TimeInterval?
    private var cycle: Cycle = .awaitingBottom
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: TricepsExtensionFormMonitor
    /// The last measured height and elbow angle, for judging a hidden hand.
    private var lastSeen: (ratio: Double, elbowAngle: Double)?

    private enum Cycle {
        case awaitingBottom
        case active(movementStart: TimeInterval, reachedTop: Bool)
    }

    private struct Reference {
        var elbowY: CGFloat
        var ruler: CGFloat
    }

    /// The tracked arm on one frame. `arm` is nil when the hand is hidden behind the head.
    private struct Observation {
        let side: BodySide
        let shoulder: CGPoint
        let elbow: CGPoint
        let arm: ArmPoints?
    }

    /// The other arm must be this much more confident before tracking switches to it.
    static let switchMargin = 0.2

    init(epoch: Int, configuration: TricepsExtensionConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = TricepsExtensionFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        guard let observation = observe(frame) else {
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }
        let side = observation.side
        if side != trackedSide {
            startTracking(side)
        }
        let time = frame.timestamp
        if let last = lastSample, time - last > configuration.maximumSampleGap {
            invalidate()
        }
        lastSample = time

        let live: Reference
        let ratio: Double
        let elbowAngle: Double
        if let arm = observation.arm {
            live = liveReference(arm)
            ratio = Double(((locked ?? live).elbowY - arm.wrist.y) / (locked ?? live).ruler)
            elbowAngle = arm.elbowAngle
            lastSeen = (ratio, elbowAngle)
        } else {
            // The hand is hidden behind the head: hold it at the start, folded, until it reappears. Before the
            // forearm has been measured, a typical forearm (about 0.89 of the upper arm) stands in as the ruler.
            let estimate = ArmGeometry.distance(observation.shoulder, observation.elbow) * 0.89
            live = Reference(elbowY: smoothedElbowY ?? observation.elbow.y, ruler: max(recentForearms.max() ?? estimate, 1))
            ratio = min(lastSeen?.ratio ?? configuration.bottomMaxRatio, configuration.bottomMaxRatio - 0.1)
            elbowAngle = min(lastSeen?.elbowAngle ?? configuration.bottomMaxElbowAngle, configuration.bottomMaxElbowAngle)
        }
        let reference = locked ?? live
        let zone = classify(ratio: ratio, elbowAngle: elbowAngle)
        let newlyConfirmed = tracker.update(zone)
        updateLock(zone: zone, live: live, at: time)

        analysis.readings[side] = ArmReading(signal: ratio, elbowAngle: elbowAngle, zone: zone)
        lastThresholds = [side: makeThresholds(elbowX: observation.elbow.x, reference: reference)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? [side] : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let form = formMonitor.update(at: time, sample: .init(ratio: ratio, elbowAngle: elbowAngle, zone: zone,
                                                              confirmed: tracker.confirmed,
                                                              tilt: upperArmTilt(shoulder: observation.shoulder, elbow: observation.elbow)),
                                      counting: counting)
        analysis.repForms = form.repForms
        analysis.formSignals = form.signals
        analysis.formReadings = formMonitor.readings

        guard counting else {
            cycle = .awaitingBottom
            return analysis
        }
        switch cycle {
        case .awaitingBottom:
            if tracker.confirmed == .bottom { cycle = .active(movementStart: time, reachedTop: false) }
        case .active(var movementStart, var reachedTop):
            if !reachedTop, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedTop = true }
            if newlyConfirmed == .bottom {
                if reachedTop, time - movementStart >= configuration.minimumRepDuration {
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                }
                movementStart = time
                reachedTop = false
            }
            cycle = .active(movementStart: movementStart, reachedTop: reachedTop)
        }
        return analysis
    }

    // MARK: - Tracking

    /// The tracked arm, followed through a hidden hand while its elbow stays raised; otherwise the arm
    /// nearer the phone. Starting with the hands already behind the head, a raised elbow is enough.
    private func observe(_ frame: PoseFrame) -> Observation? {
        if let side = trackedSide, let hidden = hiddenHand(side, in: frame) { return hidden }
        if let (side, arm) = nearArm(in: frame) {
            return Observation(side: side, shoulder: arm.shoulder, elbow: arm.elbow, arm: arm)
        }
        guard trackedSide == nil else { return nil }
        return BodySide.allCases.compactMap { hiddenHand($0, in: frame) }.first
    }

    /// The arm with its hand out of view but folded behind the head: the elbow is still raised, and the hand
    /// was last seen on its way down rather than overhead (or hasn't been seen yet).
    private func hiddenHand(_ side: BodySide, in frame: PoseFrame) -> Observation? {
        let confidence = configuration.minimumJointConfidence
        guard ArmGeometry.arm(side, in: frame, minimumConfidence: confidence) == nil,
              let shoulder = frame.point(side.shoulder, minimumConfidence: confidence),
              let elbow = frame.point(side.elbow, minimumConfidence: confidence) else { return nil }
        if let lastSeen, lastSeen.ratio >= configuration.hiddenHandMaxRatio { return nil }
        let upperArm = ArmGeometry.distance(shoulder, elbow)
        guard upperArm > 1, Double((shoulder.y - elbow.y) / upperArm) >= configuration.raisedElbowMinRise else { return nil }
        return Observation(side: side, shoulder: shoulder, elbow: elbow, arm: nil)
    }

    /// The arm nearer the phone: the most confident complete arm, keeping the current one unless the other
    /// is clearly more confident.
    private func nearArm(in frame: PoseFrame) -> (BodySide, ArmPoints)? {
        let candidates = BodySide.allCases.compactMap { side -> (BodySide, ArmPoints, Double)? in
            guard let arm = ArmGeometry.arm(side, in: frame, minimumConfidence: configuration.minimumJointConfidence) else { return nil }
            let confidence = side.armJoints.compactMap { frame.pose[$0]?.confidence }.min() ?? 0
            return (side, arm, confidence)
        }
        guard let best = candidates.max(by: { $0.2 < $1.2 }) else { return nil }
        if let current = candidates.first(where: { $0.0 == trackedSide }), best.2 - current.2 < Self.switchMargin {
            return (current.0, current.1)
        }
        return (best.0, best.1)
    }

    private func startTracking(_ side: BodySide) {
        trackedSide = side
        lastSeen = nil
        tracker.reset()
        cycle = .awaitingBottom
        recentForearms = []
        smoothedElbowY = nil
        locked = nil
        awayFromStartSince = nil
        formMonitor.invalidate()
    }

    /// A tracking gap. `lastSeen` is kept: where the hand was last seen still says whether a hidden hand
    /// is behind the head or overhead.
    private func invalidate() {
        tracker.reset()
        cycle = .awaitingBottom
        locked = nil
        awayFromStartSince = nil
        formMonitor.invalidate()
    }

    private func classify(ratio: Double, elbowAngle: Double) -> MovementZone {
        if ratio <= configuration.bottomMaxRatio, elbowAngle <= configuration.bottomMaxElbowAngle { return .bottom }
        if ratio >= configuration.topMinRatio, elbowAngle >= configuration.topMinElbowAngle { return .top }
        return .middle
    }

    private func liveReference(_ arm: ArmPoints) -> Reference {
        recentForearms.append(arm.forearmLength)
        if recentForearms.count > configuration.rulerWindow {
            recentForearms.removeFirst(recentForearms.count - configuration.rulerWindow)
        }
        let previous = smoothedElbowY ?? arm.elbow.y
        let elbowY = previous + (arm.elbow.y - previous) * configuration.elbowSmoothing
        smoothedElbowY = elbowY
        return Reference(elbowY: elbowY, ruler: max(recentForearms.max() ?? arm.forearmLength, 1))
    }

    private func updateLock(zone: MovementZone, live: Reference, at time: TimeInterval) {
        if tracker.confirmed == .bottom, zone == .bottom {
            locked = live
            awayFromStartSince = nil
            return
        }
        guard locked != nil else { return }
        let since = awayFromStartSince ?? time
        awayFromStartSince = since
        if time - since > configuration.referenceTimeout {
            locked = nil
            awayFromStartSince = nil
        }
    }

    /// The lines cross the wrist's path around the elbow, behind the head and overhead.
    private func makeThresholds(elbowX: CGFloat, reference: Reference) -> ArmThresholds {
        func line(ratio: Double, label: String) -> ThresholdLine {
            let y = reference.elbowY - CGFloat(ratio) * reference.ruler
            return ThresholdLine(from: CGPoint(x: elbowX - 0.8 * reference.ruler, y: y),
                                 to: CGPoint(x: elbowX + 0.8 * reference.ruler, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(ratio: configuration.bottomMaxRatio, label: "Start ↓"),
                             topLine: line(ratio: configuration.topMinRatio, label: "Top ↑"),
                             isLocked: locked != nil, confirmed: confirmed)
    }

    /// The upper arm's angle from straight up, in degrees.
    private func upperArmTilt(shoulder: CGPoint, elbow: CGPoint) -> Double {
        Double(atan2(elbow.x - shoulder.x, shoulder.y - elbow.y)) * 180 / .pi
    }
}

/// Watches triceps extension attempts for form cues; counting never depends on it. An attempt begins once
/// the hands settle behind the head and rise `attemptMinimumRise` forearm lengths, and ends when they
/// settle again. Times where the wrist crosses the drawn lines are interpolated between samples.
struct TricepsExtensionFormMonitor {
    struct Sample {
        let ratio: Double
        let elbowAngle: Double
        let zone: MovementZone
        let confirmed: MovementZone?
        /// Upper-arm angle from straight up, in degrees.
        let tilt: Double
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct Attempt {
        var startRatio: Double
        var peakRatio: Double
        var peakElbow: Double
        var started = false
        var reachedTop = false
        var topCrossDown: TimeInterval?
        var startCrossDown: TimeInterval?
        var lowestSinceTop: Double?
    }

    private let configuration: TricepsExtensionConfiguration
    private var attempt: Attempt?
    private var settledSamples = 0
    private var previous: (time: TimeInterval, ratio: Double)?
    private var tiltBaseline: [Double] = []
    private var tiltDrift: Double?
    private var lastDescent: TimeInterval?
    private var lastPeakElbow: Double?

    init(configuration: TricepsExtensionConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, sample: Sample, counting: Bool) -> Output {
        var output = Output()
        let settled = sample.zone == .bottom && sample.confirmed == .bottom
        settledSamples = settled ? settledSamples + 1 : 0

        if settled, tiltBaseline.count < configuration.baselineSamples { tiltBaseline.append(sample.tilt) }
        if tiltBaseline.count >= configuration.baselineSamples, !tiltBaseline.isEmpty {
            tiltDrift = abs(sample.tilt - tiltBaseline.reduce(0, +) / Double(tiltBaseline.count))
        }
        if counting, let tiltDrift, tiltDrift > configuration.elbowDriftTolerance { output.signals.insert(.tricepsElbowsUp) }

        guard counting else {
            attempt = nil
            previous = nil
            return output
        }
        defer { previous = (time: time, ratio: sample.ratio) }

        if settledSamples >= configuration.confirmationSamples {
            var waiting = Attempt(startRatio: sample.ratio, peakRatio: sample.ratio, peakElbow: sample.elbowAngle)
            if let current = attempt {
                if current.started {
                    output.repForms.append(finish(current, at: time))
                } else {
                    waiting.startRatio = min(current.startRatio, sample.ratio)
                }
            }
            attempt = waiting
            return output
        }
        guard var current = attempt else { return output }
        current.peakRatio = max(current.peakRatio, sample.ratio)
        current.peakElbow = max(current.peakElbow, sample.elbowAngle)
        if sample.ratio >= current.startRatio + configuration.attemptMinimumRise { current.started = true }
        if let last = previous {
            if let t = Self.crossingDown(of: configuration.topMinRatio, from: last, to: (time, sample.ratio)) {
                current.topCrossDown = t
                current.startCrossDown = nil
            }
            if current.topCrossDown != nil, current.startCrossDown == nil,
               let t = Self.crossingDown(of: configuration.bottomMaxRatio, from: last, to: (time, sample.ratio)) {
                current.startCrossDown = t
            }
        }
        if sample.confirmed == .top {
            current.reachedTop = true
            if sample.zone == .top {
                if let low = current.lowestSinceTop, current.peakRatio - low >= configuration.returnDip {
                    output.repForms.append(RepForm(timestamp: time, flags: [.tricepsLowerBehindHead]))
                }
                current.lowestSinceTop = nil
            } else {
                current.lowestSinceTop = min(current.lowestSinceTop ?? sample.ratio, sample.ratio)
            }
        } else {
            current.lowestSinceTop = nil
        }
        attempt = current
        return output
    }

    mutating func invalidate() {
        attempt = nil
        previous = nil
        settledSamples = 0
    }

    var readings: [FormReading] {
        func format(_ value: Double?, _ pattern: String) -> String { value.map { String(format: pattern, $0) } ?? "–" }
        return [
            FormReading(label: "↓", value: format(lastDescent, "%.2fs")),
            FormReading(label: "ext", value: format(lastPeakElbow, "%.0f°")),
            FormReading(label: "tilt", value: format(tiltDrift, "%.0f°"))
        ]
    }

    private mutating func finish(_ attempt: Attempt, at time: TimeInterval) -> RepForm {
        var flags: Set<CoachingCueID> = []
        if !attempt.reachedTop || attempt.peakElbow < configuration.fullExtensionElbowAngle {
            flags.insert(.tricepsFullExtension)
        }
        let descent = attempt.topCrossDown.flatMap { top in attempt.startCrossDown.map { $0 - top } }
        if let descent, descent < configuration.minimumDescentTime { flags.insert(.tricepsControlledLowering) }
        lastDescent = descent
        lastPeakElbow = attempt.peakElbow
        return RepForm(timestamp: time, flags: flags)
    }

    private static func crossingDown(of line: Double, from a: (time: TimeInterval, ratio: Double),
                                     to b: (time: TimeInterval, ratio: Double)) -> TimeInterval? {
        guard a.ratio >= line, b.ratio < line, a.ratio != b.ratio else { return nil }
        return a.time + (a.ratio - line) / (a.ratio - b.ratio) * (b.time - a.time)
    }
}
