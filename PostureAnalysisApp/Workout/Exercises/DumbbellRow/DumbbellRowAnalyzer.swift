import CoreGraphics
import Foundation

/// Counts one-arm rows from the side using the arm nearer the phone, which is the rowing arm. A rep is
/// hanging straight (Start), elbow pulled up past the back (Top), and hanging straight again. The session
/// runs each set one arm at a time, so every rep is credited to the set in progress.
///
/// The shoulder height and upper-arm ruler are locked while the arm hangs, so the lines hold still.
final class DumbbellRowAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: DumbbellRowConfiguration
    private var nearArm = NearArmSelector()
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var recentUpperArms: [CGFloat] = []
    private var smoothedShoulderY: CGFloat?
    private var locked: Reference?
    private var awayFromStartSince: TimeInterval?
    private var cycle: Cycle = .awaitingBottom
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: DumbbellRowFormMonitor

    private enum Cycle {
        case awaitingBottom
        case active(movementStart: TimeInterval, reachedTop: Bool)
    }

    private struct Reference {
        var shoulderY: CGFloat
        var ruler: CGFloat
    }

    init(epoch: Int, configuration: DumbbellRowConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = DumbbellRowFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        guard let (side, arm, switched) = nearArm.select(in: frame, minimumConfidence: configuration.minimumJointConfidence) else {
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }
        let time = frame.timestamp
        if switched || lastSample.map({ time - $0 > configuration.maximumSampleGap }) ?? false {
            resetTracking(keepRuler: !switched)
        }
        lastSample = time

        let live = liveReference(arm)
        let reference = locked ?? live
        let ratio = Double((reference.shoulderY - arm.elbow.y) / reference.ruler)
        let elbowAngle = arm.elbowAngle
        let zone = classify(ratio: ratio, elbowAngle: elbowAngle)
        let newlyConfirmed = tracker.update(zone)
        updateLock(zone: zone, live: live, at: time)

        analysis.readings[side] = ArmReading(signal: ratio, elbowAngle: elbowAngle, zone: zone)
        lastThresholds = [side: makeThresholds(shoulderX: arm.shoulder.x, reference: reference)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? [side] : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let back = frame.point(side.hip, minimumConfidence: configuration.minimumJointConfidence).map { hip in
            Double(atan2(arm.shoulder.y - hip.y, abs(arm.shoulder.x - hip.x))) * 180 / .pi
        }
        if !frame.estimatedJoints.isDisjoint(with: Set(side.armJoints)) {
            formMonitor.invalidate()
        }
        let form = formMonitor.update(at: time, sample: .init(ratio: ratio, zone: zone, confirmed: tracker.confirmed, backAngle: back),
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

    /// A different arm, or a tracking gap: the rep in progress can't continue.
    private func resetTracking(keepRuler: Bool) {
        tracker.reset()
        cycle = .awaitingBottom
        locked = nil
        awayFromStartSince = nil
        if !keepRuler {
            recentUpperArms = []
            smoothedShoulderY = nil
        }
        formMonitor.invalidate()
    }

    private func classify(ratio: Double, elbowAngle: Double) -> MovementZone {
        if ratio <= configuration.bottomMaxRatio, elbowAngle >= configuration.bottomMinElbowAngle { return .bottom }
        if ratio >= configuration.topMinRatio { return .top }
        return .middle
    }

    private func liveReference(_ arm: ArmPoints) -> Reference {
        recentUpperArms.append(arm.upperArmLength)
        if recentUpperArms.count > configuration.rulerWindow {
            recentUpperArms.removeFirst(recentUpperArms.count - configuration.rulerWindow)
        }
        let previous = smoothedShoulderY ?? arm.shoulder.y
        let shoulderY = previous + (arm.shoulder.y - previous) * configuration.shoulderSmoothing
        smoothedShoulderY = shoulderY
        return Reference(shoulderY: shoulderY, ruler: max(recentUpperArms.max() ?? arm.upperArmLength, 1))
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

    /// Lines across the elbow's path, under and behind the shoulder.
    private func makeThresholds(shoulderX: CGFloat, reference: Reference) -> ArmThresholds {
        func line(ratio: Double, label: String) -> ThresholdLine {
            let y = reference.shoulderY - CGFloat(ratio) * reference.ruler
            return ThresholdLine(from: CGPoint(x: shoulderX - 1.1 * reference.ruler, y: y),
                                 to: CGPoint(x: shoulderX + 1.1 * reference.ruler, y: y), label: label)
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
}

/// Watches row attempts for form cues; counting never depends on it. An attempt begins once the arm settles
/// hanging and the elbow rises `attemptMinimumRise`, and ends when the arm settles again. Times where the
/// elbow crosses the drawn lines are interpolated between samples.
struct DumbbellRowFormMonitor {
    struct Sample {
        let ratio: Double
        let zone: MovementZone
        let confirmed: MovementZone?
        /// The shoulder-to-hip line's angle above horizontal, in degrees; nil without the hip.
        let backAngle: Double?
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct Attempt {
        var startRatio: Double
        var peak: Double
        var started = false
        var reachedTop = false
        var topCrossDown: TimeInterval?
        var startCrossDown: TimeInterval?
        var lowestSinceTop: Double?
    }

    private let configuration: DumbbellRowConfiguration
    private var attempt: Attempt?
    private var settledSamples = 0
    private var previous: (time: TimeInterval, ratio: Double)?
    private var backBaseline: [Double] = []
    private var backDrift: Double?
    private var lastDescent: TimeInterval?
    private var lastPeak: Double?

    init(configuration: DumbbellRowConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, sample: Sample, counting: Bool) -> Output {
        var output = Output()
        let settled = sample.zone == .bottom && sample.confirmed == .bottom
        settledSamples = settled ? settledSamples + 1 : 0
        if let back = sample.backAngle {
            if settled, backBaseline.count < configuration.baselineSamples { backBaseline.append(back) }
            if backBaseline.count >= configuration.baselineSamples, !backBaseline.isEmpty {
                backDrift = abs(back - backBaseline.reduce(0, +) / Double(backBaseline.count))
            }
        } else {
            backDrift = nil
        }
        if counting, let backDrift, backDrift > configuration.backDriftTolerance { output.signals.insert(.rowBackStill) }

        guard counting else {
            attempt = nil
            previous = nil
            return output
        }
        defer { previous = (time: time, ratio: sample.ratio) }

        if settledSamples >= configuration.confirmationSamples {
            var waiting = Attempt(startRatio: sample.ratio, peak: sample.ratio)
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
        current.peak = max(current.peak, sample.ratio)
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
                if let low = current.lowestSinceTop, current.peak - low >= configuration.returnDip {
                    output.repForms.append(RepForm(timestamp: time, flags: [.rowStraighten]))
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
            FormReading(label: "↑", value: format(lastPeak, "%.2f")),
            FormReading(label: "↓", value: format(lastDescent, "%.2fs")),
            FormReading(label: "back", value: format(backDrift, "%.0f°"))
        ]
    }

    private mutating func finish(_ attempt: Attempt, at time: TimeInterval) -> RepForm {
        var flags: Set<CoachingCueID> = []
        if !attempt.reachedTop { flags.insert(.rowPullHigher) }
        let descent = attempt.topCrossDown.flatMap { top in attempt.startCrossDown.map { $0 - top } }
        if let descent, descent < configuration.minimumDescentTime { flags.insert(.rowControlledLowering) }
        lastDescent = descent
        lastPeak = attempt.peak
        return RepForm(timestamp: time, flags: flags)
    }

    private static func crossingDown(of line: Double, from a: (time: TimeInterval, ratio: Double),
                                     to b: (time: TimeInterval, ratio: Double)) -> TimeInterval? {
        guard a.ratio >= line, b.ratio < line, a.ratio != b.ratio else { return nil }
        return a.time + (a.ratio - line) / (a.ratio - b.ratio) * (b.time - a.time)
    }
}
