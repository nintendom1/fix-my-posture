import CoreGraphics
import Foundation

/// Counts air squats from the front: standing (Start), down to the squat (the counted end), and standing
/// again. Both legs move together, so one signal averaged over both legs drives one tracker. Following the
/// analyzers' convention, the start position is `MovementZone.bottom` and the counted end is `.top`, even
/// though the body is lowest in the squat.
final class AirSquatAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: AirSquatConfiguration
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var recentThighs: [CGFloat] = []
    private var smoothedKneeY: CGFloat?
    private var locked: Reference?
    private var awayFromStartSince: TimeInterval?
    private var cycle: Cycle = .awaitingStart
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: AirSquatFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedSquat: Bool)
    }

    /// Knee height and thigh length the hips are measured against.
    private struct Reference {
        var kneeY: CGFloat
        var ruler: CGFloat
    }

    private struct Legs {
        let hips: [BodySide: CGPoint]
        let knees: [BodySide: CGPoint]
        let ankles: [BodySide: CGPoint]
        var meanKneeY: CGFloat { (knees[.left, default: .zero].y + knees[.right, default: .zero].y) / 2 }
        var meanThigh: CGFloat {
            BodySide.allCases.map { ArmGeometry.distance(hips[$0, default: .zero], knees[$0, default: .zero]) }.reduce(0, +) / 2
        }
    }

    init(epoch: Int, configuration: AirSquatConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = AirSquatFormMonitor(configuration: configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        guard let legs = legs(in: frame) else {
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

        let live = liveReference(legs)
        let reference = locked ?? live
        var ratios: [BodySide: Double] = [:]
        for side in BodySide.allCases {
            guard let hip = legs.hips[side], let knee = legs.knees[side] else { continue }
            let ratio = Double((knee.y - hip.y) / reference.ruler)
            ratios[side] = ratio
            analysis.readings[side] = ArmReading(signal: ratio, elbowAngle: ArmGeometry.angle(at: knee, hip, legs.ankles[side] ?? knee),
                                                 zone: classify(ratio))
        }
        let ratio = ratios.values.reduce(0, +) / Double(max(ratios.count, 1))
        let zone = classify(ratio)
        let newlyConfirmed = tracker.update(zone)
        updateLock(zone: zone, live: live, at: time)

        lastThresholds = [.left: makeThresholds(legs, reference: reference)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? Set(BodySide.allCases) : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let form = formMonitor.update(at: time, sample: .init(ratio: ratio, zone: zone, confirmed: tracker.confirmed,
                                                              kneesIn: kneesIn(legs), torso: torso(frame, legs: legs, ruler: reference.ruler)),
                                      counting: counting)
        analysis.repForms = form.repForms
        analysis.formSignals = form.signals
        analysis.formReadings = formMonitor.readings

        guard counting else {
            cycle = .awaitingStart
            return analysis
        }
        switch cycle {
        case .awaitingStart:
            if tracker.confirmed == .bottom { cycle = .active(movementStart: time, reachedSquat: false) }
        case .active(var movementStart, var reachedSquat):
            if !reachedSquat, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { reachedSquat = true }
            if newlyConfirmed == .bottom {
                if reachedSquat, time - movementStart >= configuration.minimumRepDuration {
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                }
                movementStart = time
                reachedSquat = false
            }
            cycle = .active(movementStart: movementStart, reachedSquat: reachedSquat)
        }
        return analysis
    }

    private func legs(in frame: PoseFrame) -> Legs? {
        let confidence = configuration.minimumJointConfidence
        var hips: [BodySide: CGPoint] = [:]
        var knees: [BodySide: CGPoint] = [:]
        var ankles: [BodySide: CGPoint] = [:]
        for side in BodySide.allCases {
            guard let hip = frame.point(side.hip, minimumConfidence: confidence),
                  let knee = frame.point(side.knee, minimumConfidence: confidence) else { return nil }
            hips[side] = hip
            knees[side] = knee
            ankles[side] = frame.point(side.ankle, minimumConfidence: confidence)
        }
        return Legs(hips: hips, knees: knees, ankles: ankles)
    }

    /// Standing is the start (`.bottom`); the squat is the counted end (`.top`).
    private func classify(_ ratio: Double) -> MovementZone {
        if ratio >= configuration.standMinRatio { return .bottom }
        if ratio <= configuration.squatMaxRatio { return .top }
        return .middle
    }

    private func liveReference(_ legs: Legs) -> Reference {
        recentThighs.append(legs.meanThigh)
        if recentThighs.count > configuration.rulerWindow { recentThighs.removeFirst(recentThighs.count - configuration.rulerWindow) }
        let previous = smoothedKneeY ?? legs.meanKneeY
        let kneeY = previous + (legs.meanKneeY - previous) * configuration.kneeSmoothing
        smoothedKneeY = kneeY
        return Reference(kneeY: kneeY, ruler: max(recentThighs.max() ?? legs.meanThigh, 1))
    }

    /// Locked while standing, held through the squat, so the lines and the thigh ruler hold still.
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

    /// Lines across both hips: the hips rise above Stand and sink below Squat.
    private func makeThresholds(_ legs: Legs, reference: Reference) -> ArmThresholds {
        let xs = legs.hips.values.map(\.x)
        let minX = (xs.min() ?? 0) - 0.5 * reference.ruler
        let maxX = (xs.max() ?? 0) + 0.5 * reference.ruler
        func line(ratio: Double, label: String) -> ThresholdLine {
            let y = reference.kneeY - CGFloat(ratio) * reference.ruler
            return ThresholdLine(from: CGPoint(x: minX, y: y), to: CGPoint(x: maxX, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(ratio: configuration.standMinRatio, label: "Stand ↑"),
                             topLine: line(ratio: configuration.squatMaxRatio, label: "Squat ↓"),
                             isLocked: locked != nil, confirmed: confirmed)
    }

    /// How far each knee sits inside its ankle, in hip widths (positive when the knee is nearer the middle).
    private func kneesIn(_ legs: Legs) -> [BodySide: Double] {
        guard let left = legs.hips[.left], let right = legs.hips[.right] else { return [:] }
        let width = ArmGeometry.distance(left, right)
        guard width > 1 else { return [:] }
        let center = (left.x + right.x) / 2
        var result: [BodySide: Double] = [:]
        for side in BodySide.allCases {
            guard let knee = legs.knees[side], let ankle = legs.ankles[side] else { continue }
            let outward: CGFloat = ankle.x >= center ? 1 : -1
            result[side] = Double((ankle.x - knee.x) * outward / width)
        }
        return result
    }

    /// Shoulders-to-hips height in thigh lengths; nil without shoulders.
    private func torso(_ frame: PoseFrame, legs: Legs, ruler: CGFloat) -> Double? {
        let confidence = configuration.minimumJointConfidence
        guard let left = frame.point(.leftShoulder, minimumConfidence: confidence),
              let right = frame.point(.rightShoulder, minimumConfidence: confidence) else { return nil }
        let hipY = (legs.hips[.left, default: .zero].y + legs.hips[.right, default: .zero].y) / 2
        return Double((hipY - (left.y + right.y) / 2) / ruler)
    }
}

/// Watches squat attempts for form cues; counting never depends on it. An attempt begins once the user has
/// settled standing and the hips drop `attemptMinimumDrop`, and ends when they stand again. Knee and chest
/// checks compare against the user's own standing baseline and apply only while squatting.
struct AirSquatFormMonitor {
    struct Sample {
        let ratio: Double
        let zone: MovementZone
        let confirmed: MovementZone?
        let kneesIn: [BodySide: Double]
        let torso: Double?
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct Attempt {
        var standingRatio: Double
        var lowest: Double
        var started = false
        var reachedSquat = false
        /// Highest point since the hips last left the squat while it was still the confirmed checkpoint.
        var highestSinceSquat: Double?
    }

    private let configuration: AirSquatConfiguration
    private var attempt: Attempt?
    private var settledSamples = 0
    private var kneeBaseline: [BodySide: [Double]] = [:]
    private var torsoBaseline: [Double] = []
    private var kneeDrift: Double?
    private var torsoShare: Double?
    private var lastDepth: Double?

    init(configuration: AirSquatConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, sample: Sample, counting: Bool) -> Output {
        var output = Output()
        let settled = sample.zone == .bottom && sample.confirmed == .bottom
        settledSamples = settled ? settledSamples + 1 : 0
        updateBaselines(sample, settled: settled)
        if counting, sample.ratio < configuration.formDepthRatio {
            if let kneeDrift, kneeDrift > configuration.kneeInTolerance { output.signals.insert(.squatKneesOut) }
            if let torsoShare, torsoShare < configuration.minimumTorsoRatio { output.signals.insert(.squatChestUp) }
        }
        guard counting else {
            attempt = nil
            return output
        }

        if settledSamples >= configuration.confirmationSamples {
            var waiting = Attempt(standingRatio: sample.ratio, lowest: sample.ratio)
            if let current = attempt {
                if current.started {
                    lastDepth = current.lowest
                    output.repForms.append(RepForm(timestamp: time, flags: current.reachedSquat ? [] : [.squatDeeper]))
                } else {
                    waiting.standingRatio = max(current.standingRatio, sample.ratio)
                }
            }
            attempt = waiting
            return output
        }
        guard var current = attempt else { return output }
        current.lowest = min(current.lowest, sample.ratio)
        if sample.ratio <= current.standingRatio - configuration.attemptMinimumDrop { current.started = true }
        if sample.confirmed == .top {
            current.reachedSquat = true
            if sample.zone == .top {
                if let high = current.highestSinceSquat, high - current.lowest >= configuration.returnRise {
                    output.repForms.append(RepForm(timestamp: time, flags: [.squatStandUp]))
                }
                current.highestSinceSquat = nil
            } else {
                current.highestSinceSquat = max(current.highestSinceSquat ?? sample.ratio, sample.ratio)
            }
        } else {
            current.highestSinceSquat = nil
        }
        attempt = current
        return output
    }

    mutating func invalidate() {
        attempt = nil
        settledSamples = 0
    }

    var readings: [FormReading] {
        func format(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }
        return [
            FormReading(label: "depth", value: format(lastDepth)),
            FormReading(label: "knees in", value: format(kneeDrift)),
            FormReading(label: "torso", value: format(torsoShare))
        ]
    }

    private mutating func updateBaselines(_ sample: Sample, settled: Bool) {
        let needed = configuration.baselineSamples
        var drifts: [Double] = []
        for (side, value) in sample.kneesIn {
            var baseline = kneeBaseline[side] ?? []
            if settled, baseline.count < needed {
                baseline.append(value)
                kneeBaseline[side] = baseline
            }
            if baseline.count >= needed, needed > 0 { drifts.append(value - baseline.reduce(0, +) / Double(baseline.count)) }
        }
        kneeDrift = drifts.max()
        guard let torso = sample.torso else {
            torsoShare = nil
            return
        }
        if settled, torsoBaseline.count < needed { torsoBaseline.append(torso) }
        if torsoBaseline.count >= needed, needed > 0 {
            let standing = torsoBaseline.reduce(0, +) / Double(torsoBaseline.count)
            torsoShare = standing > 0 ? torso / standing : nil
        }
    }
}
