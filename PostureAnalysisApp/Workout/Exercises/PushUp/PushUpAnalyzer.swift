import CoreGraphics
import Foundation

/// Counts push-ups seen by a phone on the floor facing the head: arms straight (Up, the start), shoulders
/// down toward the hands (Down, the counted end), and up again. Both arms move together, so one signal
/// averaged over both arms drives one tracker. Following the analyzers' convention, the start position is
/// `MovementZone.bottom` and the counted end is `.top`.
///
/// The hands' height and the arm ruler are locked at the Up position, so the lines hold still.
final class PushUpAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: PushUpConfiguration
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var recentArms: [CGFloat] = []
    private var smoothedWristY: CGFloat?
    private var locked: Reference?
    private var awayFromStartSince: TimeInterval?
    private var cycle: Cycle = .awaitingStart
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: PushUpFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedDown: Bool)
    }

    private struct Reference {
        var wristY: CGFloat
        var ruler: CGFloat
    }

    init(epoch: Int, configuration: PushUpConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = PushUpFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        let confidence = configuration.minimumJointConfidence
        guard let left = ArmGeometry.arm(.left, in: frame, minimumConfidence: confidence),
              let right = ArmGeometry.arm(.right, in: frame, minimumConfidence: confidence) else {
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }
        let time = frame.timestamp
        if let last = lastSample, time - last > configuration.maximumSampleGap {
            tracker.reset()
            cycle = .awaitingStart
            locked = nil
            awayFromStartSince = nil
            formMonitor.invalidate()
        }
        lastSample = time

        let arms: [BodySide: ArmPoints] = [.left: left, .right: right]
        let live = liveReference(left: left, right: right)
        let reference = locked ?? live
        var ratios: [Double] = []
        for (side, arm) in arms {
            let ratio = Double((reference.wristY - arm.shoulder.y) / reference.ruler)
            ratios.append(ratio)
            analysis.readings[side] = ArmReading(signal: ratio, elbowAngle: arm.elbowAngle, zone: classify(ratio, arm.elbowAngle))
        }
        let ratio = ratios.reduce(0, +) / Double(ratios.count)
        let elbowAngle = (left.elbowAngle + right.elbowAngle) / 2
        let zone = classify(ratio, elbowAngle)
        let newlyConfirmed = tracker.update(zone)
        updateLock(zone: zone, live: live, at: time)

        lastThresholds = [.left: makeThresholds(left: left, right: right, reference: reference)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? Set(BodySide.allCases) : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let form = formMonitor.update(at: time, ratio: ratio, zone: zone, confirmed: tracker.confirmed, counting: counting)
        analysis.repForms = form
        analysis.formReadings = formMonitor.readings

        guard counting else {
            cycle = .awaitingStart
            return analysis
        }
        switch cycle {
        case .awaitingStart:
            if tracker.confirmed == .bottom { cycle = .active(movementStart: time, reachedDown: false) }
        case .active(var movementStart, var reachedDown):
            if !reachedDown, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedDown = true }
            if newlyConfirmed == .bottom {
                if reachedDown, time - movementStart >= configuration.minimumRepDuration {
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                }
                movementStart = time
                reachedDown = false
            }
            cycle = .active(movementStart: movementStart, reachedDown: reachedDown)
        }
        return analysis
    }

    /// Up is the start (`.bottom`); Down is the counted end (`.top`).
    private func classify(_ ratio: Double, _ elbowAngle: Double) -> MovementZone {
        if ratio >= configuration.upMinRatio, elbowAngle >= configuration.upMinElbowAngle { return .bottom }
        if ratio <= configuration.downMaxRatio, elbowAngle <= configuration.downMaxElbowAngle { return .top }
        return .middle
    }

    private func liveReference(left: ArmPoints, right: ArmPoints) -> Reference {
        recentArms.append((left.armLength + right.armLength) / 2)
        if recentArms.count > configuration.rulerWindow { recentArms.removeFirst(recentArms.count - configuration.rulerWindow) }
        let wristY = (left.wrist.y + right.wrist.y) / 2
        let previous = smoothedWristY ?? wristY
        let smoothed = previous + (wristY - previous) * configuration.wristSmoothing
        smoothedWristY = smoothed
        return Reference(wristY: smoothed, ruler: max(recentArms.max() ?? 1, 1))
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

    /// Lines across both shoulders: they rise above Up and sink below Down.
    private func makeThresholds(left: ArmPoints, right: ArmPoints, reference: Reference) -> ArmThresholds {
        let minX = min(left.shoulder.x, right.shoulder.x) - 0.3 * reference.ruler
        let maxX = max(left.shoulder.x, right.shoulder.x) + 0.3 * reference.ruler
        func line(ratio: Double, label: String) -> ThresholdLine {
            let y = reference.wristY - CGFloat(ratio) * reference.ruler
            return ThresholdLine(from: CGPoint(x: minX, y: y), to: CGPoint(x: maxX, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(ratio: configuration.upMinRatio, label: "Up ↑"),
                             topLine: line(ratio: configuration.downMaxRatio, label: "Down ↓"),
                             isLocked: locked != nil, confirmed: confirmed)
    }
}

/// Watches push-up attempts for form cues; counting never depends on it. An attempt begins once the arms
/// settle straight and the shoulders drop `attemptMinimumDrop`, and ends when the arms settle straight again.
struct PushUpFormMonitor {
    private struct Attempt {
        var upRatio: Double
        var lowest: Double
        var started = false
        var reachedDown = false
        var upCrossDown: TimeInterval?
        var downCrossDown: TimeInterval?
        var highestSinceDown: Double?
    }

    private let configuration: PushUpConfiguration
    private var attempt: Attempt?
    private var settledSamples = 0
    private var previous: (time: TimeInterval, ratio: Double)?
    private var lastDepth: Double?
    private var lastDescent: TimeInterval?

    init(configuration: PushUpConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, ratio: Double, zone: MovementZone, confirmed: MovementZone?,
                         counting: Bool) -> [RepForm] {
        var forms: [RepForm] = []
        let settled = zone == .bottom && confirmed == .bottom
        settledSamples = settled ? settledSamples + 1 : 0
        guard counting else {
            attempt = nil
            previous = nil
            return forms
        }
        defer { previous = (time: time, ratio: ratio) }

        if settledSamples >= configuration.confirmationSamples {
            var waiting = Attempt(upRatio: ratio, lowest: ratio)
            if let current = attempt {
                if current.started {
                    var flags: Set<CoachingCueID> = current.reachedDown ? [] : [.pushUpLower]
                    let descent = current.upCrossDown.flatMap { up in current.downCrossDown.map { $0 - up } }
                    if let descent, descent < configuration.minimumDescentTime { flags.insert(.pushUpControlledLowering) }
                    lastDepth = current.lowest
                    lastDescent = descent
                    forms.append(RepForm(timestamp: time, flags: flags))
                } else {
                    waiting.upRatio = max(current.upRatio, ratio)
                }
            }
            attempt = waiting
            return forms
        }
        guard var current = attempt else { return forms }
        current.lowest = min(current.lowest, ratio)
        if ratio <= current.upRatio - configuration.attemptMinimumDrop { current.started = true }
        if let last = previous {
            if current.upCrossDown == nil || current.downCrossDown != nil,
               let t = Self.crossingDown(of: configuration.upMinRatio, from: last, to: (time, ratio)) {
                current.upCrossDown = t
                current.downCrossDown = nil
            }
            if current.upCrossDown != nil, current.downCrossDown == nil,
               let t = Self.crossingDown(of: configuration.downMaxRatio, from: last, to: (time, ratio)) {
                current.downCrossDown = t
            }
        }
        if confirmed == .top {
            current.reachedDown = true
            if zone == .top {
                if let high = current.highestSinceDown, high - current.lowest >= configuration.returnRise {
                    forms.append(RepForm(timestamp: time, flags: [.pushUpFullExtension]))
                }
                current.highestSinceDown = nil
            } else {
                current.highestSinceDown = max(current.highestSinceDown ?? ratio, ratio)
            }
        } else {
            current.highestSinceDown = nil
        }
        attempt = current
        return forms
    }

    mutating func invalidate() {
        attempt = nil
        previous = nil
        settledSamples = 0
    }

    var readings: [FormReading] {
        func format(_ value: Double?, _ pattern: String) -> String { value.map { String(format: pattern, $0) } ?? "–" }
        return [
            FormReading(label: "depth", value: format(lastDepth, "%.2f")),
            FormReading(label: "↓", value: format(lastDescent, "%.2fs"))
        ]
    }

    private static func crossingDown(of line: Double, from a: (time: TimeInterval, ratio: Double),
                                     to b: (time: TimeInterval, ratio: Double)) -> TimeInterval? {
        guard a.ratio >= line, b.ratio < line, a.ratio != b.ratio else { return nil }
        return a.time + (a.ratio - line) / (a.ratio - b.ratio) * (b.time - a.time)
    }
}
