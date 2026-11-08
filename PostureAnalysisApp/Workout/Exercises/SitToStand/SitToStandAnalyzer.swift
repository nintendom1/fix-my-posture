import CoreGraphics
import Foundation

/// Counts sit-to-stands from the front: seated (Start), up to standing (the counted end), and seated again.
/// Both legs move together, so one signal averaged over both legs drives one tracker. Following the analyzers'
/// convention, the start position is `MovementZone.bottom` and the counted end is `.top`, even though the body is
/// highest when standing.
///
/// The signal is the air squat's `d`: how far the hips sit above the knees, in thigh lengths. Seated thighs
/// point at the camera and look short, so the ruler is the longest hip-to-knee length, locked while standing.
/// The lock only grows, so a near-threshold return to standing can never shrink the ruler rep after rep.
///
/// Until the first genuine stand there is no thigh ruler to lock, and the seated thigh is the wrong one. That
/// bootstrap phase measures hip-to-knee height in shin lengths instead, because the shin stays upright when
/// seated, with its own provisional Seated and genuine Standing gates. Someone who starts seated, as the
/// instructions say, arms their first cycle from the provisional Seated checkpoint. When the first stand
/// establishes the thigh ruler, the cycle carries over and its starting seat is checked against that ruler
/// before the rep counts. Someone who starts standing never reaches a seated gate, so no Seated checkpoint is
/// invented. A tracking gap clears the ruler and starts the bootstrap again.
final class SitToStandAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: SitToStandConfiguration
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var recentThighs: [CGFloat] = []
    /// Consecutive thighs from samples that read as standing before the ruler is locked.
    private var standingThighs: [CGFloat] = []
    private var longestThigh: CGFloat = 0
    private var lockedRuler: CGFloat?
    private var smoothedKneeY: CGFloat?
    private var lockedKneeY: CGFloat?
    private var cycle: Cycle = .awaitingStart
    /// Hip-to-knee height, in pixels, at the lowest the hips got in a cycle's starting seat when it was recognized
    /// before any thigh ruler existed. The rep counts only if that seat holds against the ruler the first stand
    /// establishes.
    private var provisionalSeatDrop: CGFloat?
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: SitToStandFormMonitor

    private enum Cycle {
        case awaitingStart
        case active(movementStart: TimeInterval, reachedStanding: Bool)
    }

    /// What this sample is measured against, and the lines that sort it.
    private struct Measure {
        let ruler: CGFloat
        let seatedMax: Double
        let standMin: Double
        /// The ruler is the shin, because the thigh hasn't been measured standing yet.
        let provisional: Bool
    }

    private struct Legs {
        let hips: [BodySide: CGPoint]
        let knees: [BodySide: CGPoint]
        let ankles: [BodySide: CGPoint]
        var meanKneeY: CGFloat { (knees[.left, default: .zero].y + knees[.right, default: .zero].y) / 2 }
        var meanThigh: CGFloat {
            BodySide.allCases.map { ArmGeometry.distance(hips[$0, default: .zero], knees[$0, default: .zero]) }.reduce(0, +) / 2
        }
        /// How far the knees sit below the hips on screen, in pixels, averaged over both legs.
        var meanDrop: CGFloat {
            BodySide.allCases.map { knees[$0, default: .zero].y - hips[$0, default: .zero].y }.reduce(0, +) / 2
        }
        /// Knee-to-ankle length averaged over both legs; nil unless both ankles are visible.
        var meanShin: CGFloat? {
            guard let left = ankles[.left], let right = ankles[.right] else { return nil }
            return (ArmGeometry.distance(knees[.left, default: .zero], left)
                + ArmGeometry.distance(knees[.right, default: .zero], right)) / 2
        }
    }

    init(epoch: Int, configuration: SitToStandConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = SitToStandFormMonitor(configuration: configuration)
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
            if case .active(_, let reachedStanding) = cycle, let lost = RepRejection.lost(at: time, .trackingGap(
                seconds: time - last, maximum: configuration.maximumSampleGap,
                stage: .of(reachedEnd: reachedStanding, zones: [tracker.lastZone ?? .bottom]))) {
                analysis.rejections.append(lost)
            }
            clearReference()
            tracker.reset()
            cycle = .awaitingStart
            provisionalSeatDrop = nil
            formMonitor.invalidate()
        }
        lastSample = time

        observe(legs)
        let measure = makeMeasure(legs)
        var ratios: [BodySide: Double] = [:]
        for side in BodySide.allCases {
            guard let hip = legs.hips[side], let knee = legs.knees[side] else { continue }
            let ratio = Double((knee.y - hip.y) / measure.ruler)
            ratios[side] = ratio
            analysis.readings[side] = ArmReading(signal: ratio, elbowAngle: ArmGeometry.angle(at: knee, hip, legs.ankles[side] ?? knee),
                                                 zone: classify(ratio, measure))
        }
        let ratio = ratios.values.reduce(0, +) / Double(max(ratios.count, 1))
        let zone = classify(ratio, measure)
        let newlyConfirmed = tracker.update(zone)
        updateLock(zone: zone, thigh: legs.meanThigh)

        lastThresholds = [.left: makeThresholds(legs, measure: measure)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? Set(BodySide.allCases) : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let formJoints: Set<LandmarkType> = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        if frame.estimatedJoints.isDisjoint(with: formJoints) {
            let form = formMonitor.update(at: time, sample: .init(ratio: ratio, zone: zone, confirmed: tracker.confirmed,
                                                                  kneeGapShare: kneeGapShare(legs)),
                                          counting: counting)
            analysis.repForms = form.repForms
        } else {
            formMonitor.invalidate()
        }
        analysis.formReadings = formMonitor.readings

        guard counting else {
            if case .active(_, let reachedStanding) = cycle,
               let lost = RepRejection.lost(at: time, .countingStopped(stage: .of(reachedEnd: reachedStanding, zones: [zone]))) {
                analysis.rejections.append(lost)
            }
            cycle = .awaitingStart
            provisionalSeatDrop = nil
            return analysis
        }
        switch cycle {
        case .awaitingStart:
            if tracker.confirmed == .bottom {
                cycle = .active(movementStart: time, reachedStanding: false)
                provisionalSeatDrop = measure.provisional ? legs.meanDrop : nil
            }
        case .active(var movementStart, var reachedStanding):
            if !reachedStanding, zone == .bottom {
                movementStart = time
                // The last seated sample is already on its way up, so keep the lowest the hips got.
                if measure.provisional { provisionalSeatDrop = min(provisionalSeatDrop ?? legs.meanDrop, legs.meanDrop) }
            }
            if newlyConfirmed == .top { reachedStanding = true }
            if newlyConfirmed == .bottom {
                if reachedStanding, time - movementStart >= configuration.minimumRepDuration {
                    if startingSeatHolds(against: measure.ruler) {
                        analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                    }
                } else if reachedStanding {
                    analysis.rejections.append(RepRejection(timestamp: time, reason: .tooFast(
                        duration: time - movementStart, minimum: configuration.minimumRepDuration)))
                }
                provisionalSeatDrop = nil
                movementStart = time
                reachedStanding = false
            }
            cycle = .active(movementStart: movementStart, reachedStanding: reachedStanding)
        }
        return analysis
    }

    /// A cycle that began before the thigh was measured counts only if its starting seat reads as Seated against
    /// the ruler the first stand established. Cycles that began with a ruler have nothing left to check.
    private func startingSeatHolds(against ruler: CGFloat) -> Bool {
        guard let drop = provisionalSeatDrop else { return true }
        return Double(drop / ruler) <= configuration.seatedMaxRatio
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

    /// Seated is the start (`.bottom`); standing is the counted end (`.top`).
    private func classify(_ ratio: Double, _ measure: Measure) -> MovementZone {
        if ratio <= measure.seatedMax { return .bottom }
        if ratio >= measure.standMin { return .top }
        return .middle
    }

    /// Records this sample's thigh and knee height.
    private func observe(_ legs: Legs) {
        let thigh = legs.meanThigh
        recentThighs.append(thigh)
        if recentThighs.count > configuration.rulerWindow { recentThighs.removeFirst(recentThighs.count - configuration.rulerWindow) }
        longestThigh = max(longestThigh, thigh)
        let previous = smoothedKneeY ?? legs.meanKneeY
        smoothedKneeY = previous + (legs.meanKneeY - previous) * configuration.kneeSmoothing
    }

    /// The ruler and lines for this sample. Once a stand has locked the thigh ruler, that is the ruler. Before it,
    /// the shin stands in, with its looser provisional gates. Without both ankles there is no shin, and the
    /// longest thigh seen is the ruler, which reads a seated start as standing until the first real stand.
    private func makeMeasure(_ legs: Legs) -> Measure {
        if lockedRuler == nil, let shin = legs.meanShin, shin > 1 {
            return Measure(ruler: shin, seatedMax: configuration.bootstrapSeatedMaxRatio,
                           standMin: configuration.bootstrapStandMinRatio, provisional: true)
        }
        return Measure(ruler: max(lockedRuler ?? longestThigh, 1), seatedMax: configuration.seatedMaxRatio,
                       standMin: configuration.standMinRatio, provisional: false)
    }

    /// Locks the ruler while standing, and never shortens it: a return that only just reaches the standing line
    /// has a shorter thigh on screen, and re-measuring from it would make every later rep easier to count and
    /// seating harder to reach. The third-longest recent length stands in for the longest, so one stray frame
    /// can't stretch the ruler. The first lock takes its lengths from the unbroken run of standing samples only,
    /// so the shorter thighs of the rise don't understate it. It then keeps growing from the recent window.
    private func updateLock(zone: MovementZone, thigh: CGFloat) {
        if lockedRuler == nil {
            if zone == .top {
                standingThighs.append(thigh)
                if standingThighs.count > configuration.rulerWindow {
                    standingThighs.removeFirst(standingThighs.count - configuration.rulerWindow)
                }
            } else {
                standingThighs = []
            }
        }
        guard tracker.confirmed == .top, zone == .top else { return }
        let sorted = (lockedRuler == nil ? standingThighs : recentThighs).sorted(by: >)
        let candidate = sorted.dropFirst(2).first ?? sorted.last ?? 0
        lockedRuler = max(lockedRuler ?? 0, candidate)
        lockedKneeY = smoothedKneeY
        standingThighs = []
    }

    private func clearReference() {
        recentThighs = []
        standingThighs = []
        longestThigh = 0
        lockedRuler = nil
        smoothedKneeY = nil
        lockedKneeY = nil
    }

    /// Lines across both hips: the hips sink below Seat and rise above Stand. Before the thigh is measured they
    /// sit at the provisional gates, over the shin.
    private func makeThresholds(_ legs: Legs, measure: Measure) -> ArmThresholds {
        let ruler = measure.ruler
        let kneeY = lockedKneeY ?? smoothedKneeY ?? legs.meanKneeY
        let xs = legs.hips.values.map(\.x)
        let minX = (xs.min() ?? 0) - 0.5 * ruler
        let maxX = (xs.max() ?? 0) + 0.5 * ruler
        func line(ratio: Double, label: String) -> ThresholdLine {
            let y = kneeY - CGFloat(ratio) * ruler
            return ThresholdLine(from: CGPoint(x: minX, y: y), to: CGPoint(x: maxX, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(ratio: measure.seatedMax, label: "Seat ↓"),
                             topLine: line(ratio: measure.standMin, label: "Stand ↑"),
                             isLocked: lockedRuler != nil, confirmed: confirmed)
    }

    /// The knees' horizontal gap as a share of the ankles'; nil without both ankles or with ankles nearly together.
    private func kneeGapShare(_ legs: Legs) -> Double? {
        guard let leftKnee = legs.knees[.left], let rightKnee = legs.knees[.right],
              let leftAnkle = legs.ankles[.left], let rightAnkle = legs.ankles[.right] else { return nil }
        let ankleGap = abs(leftAnkle.x - rightAnkle.x)
        guard ankleGap > 1 else { return nil }
        return Double(abs(leftKnee.x - rightKnee.x) / ankleGap)
    }
}

/// Watches sit-to-stand attempts for form cues; counting never depends on it. An attempt begins once the user has
/// settled seated and then leaves the seat for `confirmationSamples` samples. It ends on the first sample back
/// at the seat, one frame before the tracker confirms it and counts the rep, so the final rep's cue still
/// reaches the set. Only attempts that rise `attemptMinimumRise` above where the hips rested are judged.
struct SitToStandFormMonitor {
    struct Sample {
        let ratio: Double
        let zone: MovementZone
        let confirmed: MovementZone?
        let kneeGapShare: Double?
    }

    struct Output {
        var repForms: [RepForm] = []
    }

    private struct Attempt {
        let restRatio: Double
        var highest: Double
        /// The tracker confirmed standing, not one raw sample.
        var reachedStanding = false
        var lastStandingTime: TimeInterval?
        var closeKneeSamples = 0
        var kneesTooClose = false
    }

    private let configuration: SitToStandConfiguration
    private var attempt: Attempt?
    /// Where the hips rested at the last confirmed seat; nil until the user has settled seated.
    private var restRatio: Double?
    private var awaySamples = 0
    private var awayHighest: Double?
    /// Close-knee samples among the pending away samples, which the attempt inherits.
    private var awayCloseKnees = 0
    private var kneeGap: Double?
    private var lastRise: Double?
    private var lastSitDuration: TimeInterval?

    init(configuration: SitToStandConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, sample: Sample, counting: Bool) -> Output {
        var output = Output()
        kneeGap = sample.kneeGapShare
        guard counting else {
            invalidate()
            return output
        }

        if sample.zone == .bottom {
            if let current = attempt, let form = finish(current, at: time) { output.repForms.append(form) }
            attempt = nil
            awaySamples = 0
            awayHighest = nil
            awayCloseKnees = 0
            if sample.confirmed == .bottom { restRatio = sample.ratio }
            return output
        }

        guard let rest = restRatio else { return output }
        if attempt == nil {
            awaySamples += 1
            awayHighest = max(awayHighest ?? sample.ratio, sample.ratio)
            guard awaySamples >= configuration.confirmationSamples else {
                awayCloseKnees = closeKneeRun(awayCloseKnees, after: sample.kneeGapShare)
                return output
            }
            attempt = Attempt(restRatio: rest, highest: awayHighest ?? sample.ratio, closeKneeSamples: awayCloseKnees)
        }
        guard var current = attempt else { return output }
        current.highest = max(current.highest, sample.ratio)
        if sample.confirmed == .top { current.reachedStanding = true }
        if sample.zone == .top { current.lastStandingTime = time }
        if !current.reachedStanding {
            current.closeKneeSamples = closeKneeRun(current.closeKneeSamples, after: sample.kneeGapShare)
            if current.closeKneeSamples >= configuration.confirmationSamples { current.kneesTooClose = true }
        }
        attempt = current
        return output
    }

    /// Drops the attempt and waits for the next confirmed seat, as after a gap or an estimated joint.
    mutating func invalidate() {
        attempt = nil
        restRatio = nil
        awaySamples = 0
        awayHighest = nil
        awayCloseKnees = 0
    }

    /// The run of consecutive close-knee samples after one more: it grows on a close gap, restarts on a wide
    /// one, and a missing gap leaves it as it was.
    private func closeKneeRun(_ run: Int, after share: Double?) -> Int {
        guard let share else { return run }
        return share < configuration.kneeGapMinimum ? run + 1 : 0
    }

    var readings: [FormReading] {
        func format(_ value: Double?, _ pattern: String = "%.2f") -> String { value.map { String(format: pattern, $0) } ?? "–" }
        return [
            FormReading(label: "rise", value: format(lastRise)),
            FormReading(label: "sit s", value: format(lastSitDuration)),
            FormReading(label: "knee gap", value: format(kneeGap))
        ]
    }

    private mutating func finish(_ attempt: Attempt, at time: TimeInterval) -> RepForm? {
        let rise = attempt.highest - attempt.restRatio
        guard rise >= configuration.attemptMinimumRise else { return nil }
        lastRise = rise
        lastSitDuration = attempt.lastStandingTime.map { time - $0 }
        var flags: Set<CoachingCueID> = []
        if !attempt.reachedStanding {
            flags.insert(.sitToStandTall)
        } else if let sitDuration = lastSitDuration, sitDuration < configuration.minimumSitDuration {
            flags.insert(.sitToStandControl)
        }
        if attempt.kneesTooClose { flags.insert(.sitToStandKnees) }
        return RepForm(timestamp: time, flags: flags)
    }
}
