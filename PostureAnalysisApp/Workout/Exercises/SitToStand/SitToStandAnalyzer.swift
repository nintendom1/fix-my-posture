import CoreGraphics
import Foundation

/// Counts sit-to-stands from the front: seated (Start), up to standing (the counted end), and seated again.
/// The shoulder-to-ankle signal controls the stand checkpoint. A second hip-to-ankle signal corroborates the seat.
/// Both rulers grow only from robust standing windows and clear after a tracking gap or settled relocation.
final class SitToStandAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: SitToStandConfiguration
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    private var recentStandingHeights: [CGFloat] = []
    private var recentStandingHipHeights: [CGFloat] = []
    private var lockedRuler: CGFloat?
    private var lockedHipRuler: CGFloat?
    private var bootstrap: Bootstrap?
    private var cycle: Cycle?
    private var relocationAnchor: CGPoint?
    private var relocation: Relocation?
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: SitToStandFormMonitor

    private static let bootstrapStabilityRatio: CGFloat = 0.02
    private static let bootstrapHipStabilityRatio: CGFloat = 0.03
    private static let relocationSettleRatio: CGFloat = 0.02
    private static let relocationSettleDuration: TimeInterval = 1.0

    private struct Cycle {
        var movementStart: TimeInterval
        var reachedStanding: Bool
        var seatedHeight: CGFloat
        var seatedHipHeight: CGFloat
        var excursionQualified: Bool
        var ankleY: CGFloat
        var anklesPlanted = true
    }

    private struct Measurement {
        let height: CGFloat
        let hipHeight: CGFloat
        let ankleMid: CGPoint
    }

    private struct StablePlateau {
        let height: CGFloat
        let hipHeight: CGFloat
        let ankleMid: CGPoint
        let since: TimeInterval
    }

    /// A fixed candidate anchor prevents gradual movement from extending its own dwell window.
    private struct PlateauCandidate {
        let anchor: Measurement
        let since: TimeInterval
        var samples: [Measurement]

        init(_ measurement: Measurement, at time: TimeInterval) {
            anchor = measurement
            since = time
            samples = [measurement]
        }

        func accepts(_ measurement: Measurement, shoulderBand: CGFloat, hipBand: CGFloat,
                     ankleBand: CGFloat) -> Bool {
            abs(measurement.height - anchor.height) <= max(1, anchor.height * shoulderBand)
                && abs(measurement.hipHeight - anchor.hipHeight) <= max(1, anchor.hipHeight * hipBand)
                && abs(measurement.ankleMid.x - anchor.ankleMid.x) <= max(1, anchor.height * ankleBand)
                && abs(measurement.ankleMid.y - anchor.ankleMid.y) <= max(1, anchor.height * ankleBand)
        }

        mutating func append(_ measurement: Measurement, limit: Int) {
            samples.append(measurement)
            if samples.count > limit { samples.removeFirst(samples.count - limit) }
        }

        func plateau(at time: TimeInterval, minimumHold: TimeInterval) -> StablePlateau? {
            guard time - since >= minimumHold,
                  let height = robustThirdLongest(samples.map(\.height)),
                  let hipHeight = robustThirdLongest(samples.map(\.hipHeight)) else { return nil }
            return StablePlateau(height: height, hipHeight: hipHeight,
                                 ankleMid: anchor.ankleMid, since: since)
        }
    }

    /// Keeps the first confirmed pose separate from the candidate being tested for a seat or stand.
    private struct Bootstrap {
        var initial: StablePlateau?
        var highest: StablePlateau?
        var candidate: PlateauCandidate
        var provisionalSeatHeight: CGFloat?
    }

    private struct Relocation {
        var stablePoint: CGPoint
        var stableSince: TimeInterval
    }

    private enum RelocationStatus {
        case none
        case waiting
        case settled
    }

    private struct Legs {
        let shoulders: [BodySide: CGPoint]
        let hips: [BodySide: CGPoint]
        let knees: [BodySide: CGPoint]
        let ankles: [BodySide: CGPoint]

        var ankleMid: CGPoint { midpoint(ankles[.left] ?? .zero, ankles[.right] ?? .zero) }
        var shoulderMid: CGPoint { midpoint(shoulders[.left] ?? .zero, shoulders[.right] ?? .zero) }
        var hipMid: CGPoint { midpoint(hips[.left] ?? .zero, hips[.right] ?? .zero) }
        var upperBodyHeight: CGFloat { max(ankleMid.y - shoulderMid.y, 1) }
        var hipToAnkleHeight: CGFloat { max(ankleMid.y - hipMid.y, 1) }
        var kneeGapShare: Double? {
            guard let leftKnee = knees[.left], let rightKnee = knees[.right],
                  let leftAnkle = ankles[.left], let rightAnkle = ankles[.right] else { return nil }
            let ankleGap = abs(leftAnkle.x - rightAnkle.x)
            guard ankleGap > 1 else { return nil }
            return Double(abs(leftKnee.x - rightKnee.x) / ankleGap)
        }

        private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
            CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
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
        if let lastSample, time - lastSample > configuration.maximumSampleGap {
            if let cycle,
               let lost = RepRejection.lost(at: time, .trackingGap(
                seconds: time - lastSample, maximum: configuration.maximumSampleGap,
                stage: .of(reachedEnd: cycle.reachedStanding, zones: [tracker.lastZone ?? .middle]))) {
                analysis.rejections.append(lost)
            }
            clearReference()
            tracker.reset()
            cycle = nil
            formMonitor.invalidate()
        }
        lastSample = time

        switch updateRelocation(ankleMid: legs.ankleMid, height: legs.upperBodyHeight, at: time) {
        case .none:
            break
        case .waiting:
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        case .settled:
            clearReference()
            tracker.reset()
            cycle = nil
            formMonitor.invalidate()
        }

        let height = legs.upperBodyHeight
        let hipHeight = legs.hipToAnkleHeight
        let sample = updateSample(legs, time: time, height: height, hipHeight: hipHeight)
        let ratio = sample.ratio
        let zone = sample.zone
        let newlyConfirmed = sample.newlyConfirmed

        for side in BodySide.allCases {
            guard let hip = legs.hips[side], let ankle = legs.ankles[side] else { continue }
            let kneeAngle: Double
            if let knee = legs.knees[side] {
                kneeAngle = ArmGeometry.angle(at: knee, hip, ankle)
            } else {
                kneeAngle = 180
            }
            analysis.readings[side] = ArmReading(signal: ratio, elbowAngle: kneeAngle, zone: zone)
        }
        lastThresholds = [.left: makeThresholds(legs, ruler: sample.ruler)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? Set(BodySide.allCases) : []
        analysis.startPositionHeld = tracker.confirmed == .bottom && zone == .bottom

        let formJoints: Set<LandmarkType> = [
            .leftShoulder, .rightShoulder, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
        ]
        if let seatedHeight = sample.seededSeatHeight {
            formMonitor.seedSeated(height: Double(seatedHeight))
        }
        if frame.estimatedJoints.isDisjoint(with: formJoints) {
            let form = formMonitor.update(
                at: time,
                sample: .init(height: Double(height), ruler: Double(lockedRuler ?? sample.ruler),
                              zone: sample.provisionalSeatHeld ? .bottom : zone,
                              confirmed: sample.provisionalSeatHeld ? .bottom : tracker.confirmed,
                              newlyConfirmed: newlyConfirmed,
                              kneeGapShare: legs.kneeGapShare),
                counting: counting
            )
            analysis.repForms = form.repForms
        } else {
            formMonitor.invalidate()
        }
        analysis.formReadings = formMonitor.readings

        guard counting else {
            if let cycle,
               let lost = RepRejection.lost(at: time, .countingStopped(
                stage: .of(reachedEnd: cycle.reachedStanding, zones: [zone]))) {
                analysis.rejections.append(lost)
            }
            cycle = nil
            return analysis
        }

        if cycle == nil, sample.seatRecognized {
            cycle = Cycle(movementStart: time, reachedStanding: false, seatedHeight: height,
                          seatedHipHeight: hipHeight, excursionQualified: false,
                          ankleY: legs.ankleMid.y)
        }
        if var current = cycle {
            if abs(legs.ankleMid.y - current.ankleY) > height * CGFloat(configuration.ankleStabilityRatio) {
                current.anklesPlanted = false
            }
            if newlyConfirmed == .top {
                current.reachedStanding = true
            }
            if zone == .top, tracker.confirmed == .top {
                let excursion = Double((height - current.seatedHeight) / max(sample.ruler, 1))
                current.excursionQualified = current.excursionQualified
                    || excursion >= configuration.minimumRepExcursionRatio
            }
            if newlyConfirmed == .bottom {
                if current.reachedStanding {
                    let seatedRatio = Double(current.seatedHeight / max(sample.ruler, 1))
                    let seatedHipRatio = Double(current.seatedHipHeight / max(sample.hipRuler, 1))
                    let validSeat = seatedRatio <= configuration.seatedMaxRatio
                        && seatedHipRatio <= configuration.hipSeatedMaxRatio
                    let duration = time - current.movementStart
                    if validSeat, current.excursionQualified, current.anklesPlanted,
                       duration >= configuration.minimumRepDuration {
                        analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time,
                                                           sides: Set(BodySide.allCases)))
                    } else if current.anklesPlanted, duration < configuration.minimumRepDuration {
                        analysis.rejections.append(RepRejection(timestamp: time, reason: .tooFast(
                            duration: duration, minimum: configuration.minimumRepDuration)))
                    }
                }
                current = Cycle(movementStart: time, reachedStanding: false, seatedHeight: height,
                                seatedHipHeight: hipHeight, excursionQualified: false,
                                ankleY: legs.ankleMid.y)
            }
            cycle = current
        } else if tracker.confirmed == .bottom {
            cycle = Cycle(movementStart: time, reachedStanding: false, seatedHeight: height,
                          seatedHipHeight: hipHeight, excursionQualified: false,
                          ankleY: legs.ankleMid.y)
        }
        return analysis
    }

    private func legs(in frame: PoseFrame) -> Legs? {
        let confidence = configuration.minimumJointConfidence
        var shoulders: [BodySide: CGPoint] = [:]
        var hips: [BodySide: CGPoint] = [:]
        var knees: [BodySide: CGPoint] = [:]
        var ankles: [BodySide: CGPoint] = [:]
        for side in BodySide.allCases {
            guard let shoulder = frame.point(side.shoulder, minimumConfidence: confidence),
                  let hip = frame.point(side.hip, minimumConfidence: confidence),
                  let ankle = frame.point(side.ankle, minimumConfidence: confidence) else { return nil }
            hips[side] = hip
            ankles[side] = ankle
            shoulders[side] = shoulder
            knees[side] = frame.point(side.knee, minimumConfidence: configuration.minimumKneeConfidence)
        }
        return Legs(shoulders: shoulders, hips: hips, knees: knees, ankles: ankles)
    }

    private func clearReference() {
        bootstrap = nil
        recentStandingHeights = []
        recentStandingHipHeights = []
        lockedRuler = nil
        lockedHipRuler = nil
        relocationAnchor = nil
        relocation = nil
    }

    private func updateSample(_ legs: Legs, time: TimeInterval, height: CGFloat, hipHeight: CGFloat) -> Sample {
        guard let currentRuler = lockedRuler, let currentHipRuler = lockedHipRuler else {
            let event = updateBootstrap(legs, time: time, height: height, hipHeight: hipHeight)
            let ruler = max(lockedRuler ?? bootstrap?.highest?.height ?? bootstrap?.initial?.height ?? height, 1)
            let hipRuler = max(lockedHipRuler ?? bootstrap?.highest?.hipHeight ?? bootstrap?.initial?.hipHeight ?? hipHeight, 1)
            let ratio = Double(height / ruler)
            return Sample(ruler: ruler, hipRuler: hipRuler, ratio: ratio,
                          zone: event?.zone ?? .middle,
                          newlyConfirmed: event?.newlyConfirmed,
                          seatRecognized: event?.seatRecognized ?? false,
                          seededSeatHeight: event?.seededSeatHeight,
                          provisionalSeatHeld: event?.provisionalSeatHeld ?? false)
        }

        let ruler = max(currentRuler, 1)
        let hipRuler = max(currentHipRuler, 1)
        let ratio = Double(height / ruler)
        let hipRatio = Double(hipHeight / hipRuler)
        let zone = classify(ratio, hipRatio: hipRatio)
        let confirmed = tracker.update(zone)
        updateStandingRuler(zone: zone, height: height, hipHeight: hipHeight)
        return Sample(ruler: ruler, hipRuler: hipRuler, ratio: ratio, zone: zone, newlyConfirmed: confirmed,
                      seatRecognized: confirmed == .bottom, seededSeatHeight: nil,
                      provisionalSeatHeld: false)
    }

    private struct Sample {
        let ruler: CGFloat
        let hipRuler: CGFloat
        let ratio: Double
        let zone: MovementZone
        let newlyConfirmed: MovementZone?
        let seatRecognized: Bool
        let seededSeatHeight: CGFloat?
        let provisionalSeatHeld: Bool
    }

    private struct BootstrapEvent {
        let zone: MovementZone
        let newlyConfirmed: MovementZone?
        let seatRecognized: Bool
        let seededSeatHeight: CGFloat?
        let provisionalSeatHeld: Bool
    }

    /// Learns whether the first stable pose is seated or standing from the direction of the first transition.
    private func updateBootstrap(_ legs: Legs, time: TimeInterval, height: CGFloat, hipHeight: CGFloat) -> BootstrapEvent? {
        let measurement = Measurement(height: height, hipHeight: hipHeight, ankleMid: legs.ankleMid)
        if bootstrap == nil {
            bootstrap = Bootstrap(initial: nil, highest: nil,
                                  candidate: PlateauCandidate(measurement, at: time),
                                  provisionalSeatHeight: nil)
        }
        guard var state = bootstrap else { return nil }

        if let initial = state.initial {
            let riseFromInitial = Double(measurement.height / max(initial.height, 1))
            if state.provisionalSeatHeight == nil, riseFromInitial >= 1.03, riseFromInitial < 1.5 {
                state.provisionalSeatHeight = initial.height
            }
        }

        if state.candidate.accepts(measurement,
                                   shoulderBand: Self.bootstrapStabilityRatio,
                                   hipBand: Self.bootstrapHipStabilityRatio,
                                   ankleBand: Self.relocationSettleRatio) {
            state.candidate.append(measurement, limit: max(configuration.rulerWindow, 3))
        } else {
            state.candidate = PlateauCandidate(measurement, at: time)
        }
        guard let plateau = state.candidate.plateau(at: time, minimumHold: configuration.minimumReferenceHold) else {
            bootstrap = state
            return nil
        }

        guard let initial = state.initial else {
            state.initial = plateau
            state.highest = plateau
            bootstrap = state
            return BootstrapEvent(zone: .middle, newlyConfirmed: nil, seatRecognized: false,
                                  seededSeatHeight: plateau.height, provisionalSeatHeld: false)
        }

        let sameShoulderHeight = abs(plateau.height - initial.height)
            <= max(1, initial.height * Self.bootstrapStabilityRatio)
        let sameAsInitial = sameShoulderHeight
            && abs(plateau.hipHeight - initial.hipHeight) <= max(1, initial.hipHeight * Self.bootstrapHipStabilityRatio)
        if sameAsInitial {
            bootstrap = state
            guard state.provisionalSeatHeight != nil else { return nil }
            return BootstrapEvent(zone: .middle, newlyConfirmed: nil, seatRecognized: false,
                                  seededSeatHeight: nil, provisionalSeatHeld: true)
        }
        if state.provisionalSeatHeight != nil, sameShoulderHeight {
            bootstrap = state
            return BootstrapEvent(zone: .middle, newlyConfirmed: nil, seatRecognized: false,
                                  seededSeatHeight: nil, provisionalSeatHeld: true)
        }

        let reference = state.highest ?? initial
        let feetPlanted = abs(plateau.ankleMid.x - reference.ankleMid.x) <= max(1, reference.height * CGFloat(configuration.ankleStabilityRatio))
            && abs(plateau.ankleMid.y - reference.ankleMid.y) <= max(1, reference.height * CGFloat(configuration.ankleStabilityRatio))
        guard feetPlanted else {
            state.initial = plateau
            state.highest = plateau
            state.candidate = PlateauCandidate(measurement, at: time)
            bootstrap = state
            return nil
        }

        let seatAgainstReference = Double(plateau.height / max(reference.height, 1)) <= configuration.seatedMaxRatio
            && Double(plateau.hipHeight / max(reference.hipHeight, 1)) <= configuration.hipSeatedMaxRatio
        if seatAgainstReference {
            lockedRuler = reference.height
            lockedHipRuler = reference.hipHeight
            relocationAnchor = reference.ankleMid
            seedTracker(start: .top, end: .bottom)
            cycle = Cycle(movementStart: time, reachedStanding: false, seatedHeight: plateau.height,
                          seatedHipHeight: plateau.hipHeight, excursionQualified: false,
                          ankleY: plateau.ankleMid.y)
            bootstrap = nil
            return BootstrapEvent(zone: .bottom, newlyConfirmed: .bottom, seatRecognized: true,
                                  seededSeatHeight: nil, provisionalSeatHeld: false)
        }

        let riseRatio = configuration.partial ? configuration.partialBootstrapStandRiseRatio
            : configuration.bootstrapStandRiseRatio
        if Double(plateau.height / max(initial.height, 1)) >= riseRatio,
           let standingHeight = robustThirdLongest(state.candidate.samples.map(\.height)),
           let standingHipHeight = robustThirdLongest(state.candidate.samples.map(\.hipHeight)) {
            lockedRuler = standingHeight
            lockedHipRuler = standingHipHeight
            relocationAnchor = plateau.ankleMid
            seedTracker(start: .bottom, end: .top)
            cycle = Cycle(movementStart: initial.since, reachedStanding: true,
                          seatedHeight: initial.height, seatedHipHeight: initial.hipHeight,
                          excursionQualified: Double((standingHeight - initial.height) / max(standingHeight, 1))
                            >= configuration.minimumRepExcursionRatio,
                          ankleY: initial.ankleMid.y)
            bootstrap = nil
            return BootstrapEvent(zone: .top, newlyConfirmed: .top, seatRecognized: false,
                                  seededSeatHeight: nil, provisionalSeatHeld: false)
        }

        if Double(plateau.height / max(reference.height, 1)) > 1.02,
           let standingHeight = robustThirdLongest(state.candidate.samples.map(\.height)),
           let standingHipHeight = robustThirdLongest(state.candidate.samples.map(\.hipHeight)) {
            state.highest = StablePlateau(height: standingHeight, hipHeight: standingHipHeight,
                                          ankleMid: plateau.ankleMid, since: plateau.since)
        }
        bootstrap = state
        return nil
    }

    private func seedTracker(start: MovementZone, end: MovementZone) {
        tracker.reset()
        for _ in 0..<configuration.confirmationSamples { _ = tracker.update(start) }
        for _ in 0..<configuration.confirmationSamples { _ = tracker.update(end) }
    }

    private func classify(_ ratio: Double, hipRatio: Double) -> MovementZone {
        if ratio <= configuration.seatedMaxRatio, hipRatio <= configuration.hipSeatedMaxRatio { return .bottom }
        if ratio >= configuration.standMinRatio { return .top }
        return .middle
    }

    /// Both standing rulers grow from robust windows only and retain their previous value until three samples exist.
    private func updateStandingRuler(zone: MovementZone, height: CGFloat, hipHeight: CGFloat) {
        guard zone == .top, tracker.confirmed == .top else {
            recentStandingHeights = []
            recentStandingHipHeights = []
            return
        }
        recentStandingHeights.append(height)
        recentStandingHipHeights.append(hipHeight)
        if recentStandingHeights.count > configuration.rulerWindow {
            recentStandingHeights.removeFirst(recentStandingHeights.count - configuration.rulerWindow)
        }
        if recentStandingHipHeights.count > configuration.rulerWindow {
            recentStandingHipHeights.removeFirst(recentStandingHipHeights.count - configuration.rulerWindow)
        }
        guard let robustHeight = robustThirdLongest(recentStandingHeights),
              let robustHipHeight = robustThirdLongest(recentStandingHipHeights) else { return }
        lockedRuler = max(lockedRuler ?? 0, robustHeight)
        lockedHipRuler = max(lockedHipRuler ?? 0, robustHipHeight)
    }

    private func updateRelocation(ankleMid: CGPoint, height: CGFloat, at time: TimeInterval) -> RelocationStatus {
        guard lockedRuler != nil, let anchor = relocationAnchor else { return .none }
        let ruler = max(lockedRuler ?? height, 1)
        if var pending = relocation {
            let movedAgain = abs(ankleMid.x - pending.stablePoint.x) > max(1, ruler * Self.relocationSettleRatio)
                || abs(ankleMid.y - pending.stablePoint.y) > max(1, ruler * Self.relocationSettleRatio)
            if movedAgain {
                pending.stablePoint = ankleMid
                pending.stableSince = time
                relocation = pending
                return .waiting
            }
            return time - pending.stableSince >= Self.relocationSettleDuration ? .settled : .waiting
        }

        let relocated = abs(ankleMid.x - anchor.x) > max(1, ruler * configuration.ankleStabilityRatio)
            || abs(ankleMid.y - anchor.y) > max(1, ruler * configuration.ankleStabilityRatio)
        guard relocated else { return .none }
        relocation = Relocation(stablePoint: ankleMid, stableSince: time)
        return .waiting
    }

    /// The displayed Seat and Stand lines use the same shoulder-to-ankle units as the tracker.
    private func makeThresholds(_ legs: Legs, ruler: CGFloat) -> ArmThresholds {
        let ruler = max(ruler, 1)
        let halfWidth = max(8, ruler * 0.2)
        let centerX = legs.shoulderMid.x
        func line(ratio: Double, label: String) -> ThresholdLine {
            let y = legs.ankleMid.y - CGFloat(ratio) * ruler
            return ThresholdLine(from: CGPoint(x: centerX - halfWidth, y: y),
                                 to: CGPoint(x: centerX + halfWidth, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(ratio: configuration.seatedMaxRatio, label: "Seat ↓"),
                             topLine: line(ratio: configuration.standMinRatio, label: "Stand ↑"),
                             isLocked: lockedRuler != nil, confirmed: confirmed)
    }
}

/// Watches sit-to-stand attempts for form cues; counting never depends on it. An attempt begins once the user has
/// settled seated and then leaves the seat for `confirmationSamples` samples. It ends on the first sample back at
/// the seat, one frame before the tracker confirms it and counts the rep.
struct SitToStandFormMonitor {
    struct Sample {
        let height: Double
        let ruler: Double
        let zone: MovementZone
        let confirmed: MovementZone?
        let newlyConfirmed: MovementZone?
        let kneeGapShare: Double?
    }

    struct Output {
        var repForms: [RepForm] = []
    }

    private struct Attempt {
        let restHeight: Double
        var highest: Double
        /// The tracker confirmed standing, not one raw sample.
        var reachedStanding = false
        var standingPlateau = false
        /// The first sample leaving a confirmed standing plateau starts the descent timer.
        var lastStandingTime: TimeInterval?
        var closeKneeSamples = 0
        var kneesTooClose = false
    }

    private let configuration: SitToStandConfiguration
    private var attempt: Attempt?
    /// Physical shoulder-to-ankle `u` at the last confirmed seat.
    private var restHeight: Double?
    private var awaySamples = 0
    private var awayHighest: Double?
    /// Close-knee samples among pending away samples, which the attempt inherits.
    private var awayCloseKnees = 0
    private var kneeGap: Double?
    private var lastRise: Double?
    private var lastSitDuration: TimeInterval?

    init(configuration: SitToStandConfiguration) {
        self.configuration = configuration
    }

    mutating func seedSeated(height: Double) {
        restHeight = height
    }

    mutating func update(at time: TimeInterval, sample: Sample, counting: Bool) -> Output {
        var output = Output()
        kneeGap = sample.kneeGapShare
        guard counting else {
            invalidate()
            return output
        }

        if sample.zone == .bottom {
            if let current = attempt, let form = finish(current, at: time, ruler: sample.ruler) {
                output.repForms.append(form)
            }
            attempt = nil
            awaySamples = 0
            awayHighest = nil
            awayCloseKnees = 0
            if sample.confirmed == .bottom { restHeight = sample.height }
            return output
        }

        guard let restHeight else { return output }
        var beganThisSample = false
        if attempt == nil {
            awaySamples += 1
            awayHighest = max(awayHighest ?? sample.height, sample.height)
            guard awaySamples >= configuration.confirmationSamples else {
                awayCloseKnees = closeKneeRun(awayCloseKnees, after: sample.kneeGapShare)
                return output
            }
            attempt = Attempt(restHeight: restHeight, highest: awayHighest ?? sample.height,
                             closeKneeSamples: awayCloseKnees)
            beganThisSample = true
        }
        guard var current = attempt else { return output }
        current.highest = max(current.highest, sample.height)
        if sample.zone == .top {
            if current.standingPlateau {
                current.lastStandingTime = time
            } else if sample.newlyConfirmed == .top {
                current.reachedStanding = true
                current.standingPlateau = true
                current.lastStandingTime = time
            }
        } else {
            if current.standingPlateau {
                current.standingPlateau = false
            }
        }
        // Bootstrap may take a dwell window to lock Stand; stop sampling knees once the pose is physically tall.
        let minimumKneeCueRise = configuration.partial ? 1.15 : 1.20
        let hasRisen = current.highest > current.restHeight + sample.ruler * 0.02
        let isBelowStandingPlateau = current.highest / max(current.restHeight, 1) < minimumKneeCueRise
        if (!current.reachedStanding || beganThisSample), hasRisen, isBelowStandingPlateau {
            current.closeKneeSamples = closeKneeRun(current.closeKneeSamples, after: sample.kneeGapShare)
            if current.closeKneeSamples >= configuration.confirmationSamples { current.kneesTooClose = true }
        } else if !current.kneesTooClose {
            current.closeKneeSamples = 0
        }
        attempt = current
        return output
    }

    mutating func invalidate() {
        attempt = nil
        restHeight = nil
        awaySamples = 0
        awayHighest = nil
        awayCloseKnees = 0
    }

    private func closeKneeRun(_ run: Int, after share: Double?) -> Int {
        guard let share else { return 0 }
        return share < configuration.kneeGapMinimum ? run + 1 : 0
    }

    var readings: [FormReading] {
        func format(_ value: Double?, _ pattern: String = "%.2f") -> String {
            value.map { String(format: pattern, $0) } ?? "–"
        }
        return [
            FormReading(label: "rise", value: format(lastRise)),
            FormReading(label: "sit s", value: format(lastSitDuration)),
            FormReading(label: "knee gap", value: format(kneeGap))
        ]
    }

    private mutating func finish(_ attempt: Attempt, at time: TimeInterval, ruler: Double) -> RepForm? {
        guard ruler > 0 else { return nil }
        let rise = (attempt.highest - attempt.restHeight) / ruler
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

private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
    CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
}

private func robustThirdLongest(_ heights: [CGFloat]) -> CGFloat? {
    guard heights.count >= 3 else { return nil }
    return heights.sorted(by: >).dropFirst(2).first
}
