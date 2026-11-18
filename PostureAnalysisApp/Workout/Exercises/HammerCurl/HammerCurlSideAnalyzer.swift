import CoreGraphics
import Foundation

/// Side-on thresholds and timing. The fields stay flat so recordings can be tuned independently of the front view.
struct HammerCurlSideConfiguration: Codable, Equatable {
    /// Start: the wrist hangs this far below the elbow in forearm lengths.
    var bottomMaxRatio: Double = -0.8
    /// Start also requires a nearly straight elbow.
    var bottomMinElbowAngle: Double = 140
    /// Top: the wrist rises this far above the elbow in forearm lengths.
    var topMinRatio: Double = 0.45
    /// Maximum elbow drift from the shoulder in upper-arm lengths.
    var elbowDriftTolerance: Double = 0.35
    /// Maximum shoulder movement relative to the hip in upper-arm lengths.
    var swayTolerance: Double = 0.35
    var confirmationSamples = 2
    var minimumRepDuration: TimeInterval = 0.8
    var maximumSampleGap: TimeInterval = 0.28
    var minimumJointConfidence: Double = 0.4
    var rulerWindow = 10
    var elbowSmoothing: CGFloat = 0.4
    var referenceTimeout: TimeInterval = 6

    static let standard = HammerCurlSideConfiguration()
}

/// Counts side-on hammer curls from the arm nearer the phone. Each completed rep is credited to both sides.
/// The wrist height is measured in the longest recent forearm length, which remains a useful ruler as the arm curls.
final class HammerCurlSideAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: HammerCurlSideConfiguration
    private var nearArm = NearArmSelector()
    private var trackingSide: BodySide?
    private var tracker: HysteresisPhaseTracker
    private var lastSample: TimeInterval?
    /// When the tracker last confirmed the start.
    private var startConfirmedAt: TimeInterval?
    /// The last frame processed without counting. An arm unseen since then would have lost its attempt.
    private var countingStoppedAt: TimeInterval?
    private var recentForearms: [CGFloat] = []
    private var recentUpperArms: [CGFloat] = []
    private var smoothedElbowY: CGFloat?
    private var locked: Reference?
    private var awayFromStartSince: TimeInterval?
    private var cycle: Cycle = .awaitingStart
    private var lastThresholds: [BodySide: ArmThresholds] = [:]
    private var formMonitor: HammerCurlFormMonitor

    private enum Cycle {
        case awaitingStart
        /// `topReachedAt` is when the arm reached the top, nil until then.
        case active(movementStart: TimeInterval, topReachedAt: TimeInterval?)
    }

    private struct Reference {
        var elbowY: CGFloat
        var ruler: CGFloat
    }

    init(epoch: Int, configuration: HammerCurlSideConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        formMonitor = Self.makeFormMonitor(configuration)
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        var analysis = ExerciseAnalysis()
        if !counting { countingStoppedAt = frame.timestamp }
        guard let selected = nearArm.select(in: frame, minimumConfidence: configuration.minimumJointConfidence) else {
            analysis.thresholds = lastThresholds
            analysis.formReadings = formMonitor.readings
            return analysis
        }

        let side = selected.side
        let arm = selected.arm
        let time = frame.timestamp
        let gap = lastSample.map { time - $0 } ?? 0
        let hadGap = lastSample != nil && gap > configuration.maximumSampleGap
        defer {
            if hadGap { nearArm = NearArmSelector() }
        }
        let switched = trackingSide.map { $0 != side } ?? false
        if switched || hadGap {
            let stage = activeStage
            if switched, let rejection = RepRejection.lost(at: time, .sideSwitched(stage: stage ?? .atStart)) {
                analysis.rejections.append(rejection)
            } else if hadGap, let rejection = RepRejection.lost(at: time, .trackingGap(
                seconds: gap, maximum: configuration.maximumSampleGap, stage: stage ?? .atStart)) {
                analysis.rejections.append(rejection)
            }
            resetTracking()
        }
        trackingSide = side
        lastSample = time

        let live = liveReference(for: arm)
        if locked != nil, let awayFromStartSince,
           time - awayFromStartSince > configuration.referenceTimeout {
            if let rejection = RepRejection.lost(at: time, .referenceExpired(stage: activeStage ?? .atStart)) {
                analysis.rejections.append(rejection)
            }
            tracker.reset()
            startConfirmedAt = nil
            cycle = .awaitingStart
            locked = nil
            self.awayFromStartSince = nil
            formMonitor.invalidate(side)
        }
        let reference = locked ?? live
        let signal = Double((reference.elbowY - arm.wrist.y) / max(reference.ruler, 1))
        let zone = classify(signal: signal, elbowAngle: arm.elbowAngle)
        let newlyConfirmed = tracker.update(zone)
        if newlyConfirmed == .bottom { startConfirmedAt = time }
        updateLock(zone: zone, live: live, at: time)

        analysis.readings[side] = ArmReading(signal: signal, elbowAngle: arm.elbowAngle, zone: zone)
        let thresholdReference = locked ?? live
        lastThresholds = [side: makeThresholds(arm: arm, facing: facing(arm, in: frame), reference: thresholdReference)]
        analysis.thresholds = lastThresholds
        analysis.endPositionSides = tracker.confirmed == .top ? [side] : []
        analysis.startPositionHeld = tracker.confirmed == .bottom

        let upperArm = max(recentUpperArms.max() ?? arm.upperArmLength, 1)
        let formSample = HammerCurlFormMonitor.ArmSample(
            ratio: signal,
            zone: zone,
            confirmed: tracker.confirmed,
            flare: Double(abs(arm.elbow.x - arm.shoulder.x) / upperArm)
        )
        let focusJoints: Set<LandmarkType> = [
            .leftShoulder, .leftElbow, .leftWrist,
            .rightShoulder, .rightElbow, .rightWrist,
            .leftHip, .rightHip
        ]
        if !frame.estimatedJoints.isDisjoint(with: focusJoints) {
            formMonitor.invalidate(side)
            analysis.formReadings = formMonitor.readings
        } else {
            let form = formMonitor.update(at: time, arms: [side: formSample],
                                          sway: sway(side: side, arm: arm, upperArm: upperArm, in: frame),
                                          counting: counting)
            analysis.repForms = form.repForms
            analysis.formSignals = form.signals
            analysis.formReadings = formMonitor.readings
        }

        guard counting else {
            if let rejection = RepRejection.lost(at: time, .countingStopped(stage: activeStage ?? .atStart)) {
                if case .active = cycle { analysis.rejections.append(rejection) }
            }
            cycle = .awaitingStart
            return analysis
        }

        switch cycle {
        case .awaitingStart:
            if tracker.confirmed == .bottom {
                cycle = .active(movementStart: time, topReachedAt: nil)
            }
        case .active(var movementStart, var topReachedAt):
            if topReachedAt == nil, zone == .bottom { movementStart = time }
            if newlyConfirmed == .top { topReachedAt = topReachedAt ?? time }
            // Only a resumed attempt can be past the top while the tracker holds the start: this view confirmed the
            // return during its warm-up, so the attempt ends on this first counting frame.
            if newlyConfirmed == .bottom || (topReachedAt != nil && tracker.confirmed == .bottom) {
                if topReachedAt != nil {
                    let duration = time - movementStart
                    if duration >= configuration.minimumRepDuration {
                        analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                    } else {
                        analysis.rejections.append(RepRejection(timestamp: time, reason: .tooFast(
                            duration: duration, minimum: configuration.minimumRepDuration)))
                    }
                }
                movementStart = time
                topReachedAt = nil
            }
            cycle = .active(movementStart: movementStart, topReachedAt: topReachedAt)
        }

        return analysis
    }

    // MARK: - Camera-view hand-off

    /// The tracked arm's curl past the Top line, for both sides, since one rep here credits both. It carries while
    /// the arm is hidden, unless counting stopped after it was last seen.
    func attemptInProgress() -> RepAttemptInProgress? {
        guard case .active(let start, let top?) = cycle, let lastSample,
              countingStoppedAt.map({ $0 < lastSample }) ?? true else { return nil }
        return RepAttemptInProgress(movementStart: start, reachedEnd: top, sides: Set(BodySide.allCases))
    }

    /// Any carried side continues on the tracked arm, which counts it once its own tracker confirms the start.
    func resume(_ attempt: RepAttemptInProgress) {
        guard !attempt.sides.isEmpty, let trackingSide, lastSample != nil else { return }
        // Side-on credits both arms for each near-arm curl, so the far arm's curl counts here only when it completes
        // a pair; otherwise the near arm's next curl completes it.
        let pairSides = attempt.sides.union(attempt.pairCredits)
        guard attempt.sides.contains(trackingSide) || pairSides.isSuperset(of: BodySide.allCases) else { return }
        if case .active(_, .some) = cycle { return }
        if tracker.confirmed == .bottom, (startConfirmedAt ?? -.infinity) <= attempt.reachedEnd { return }
        cycle = .active(movementStart: attempt.movementStart, topReachedAt: attempt.reachedEnd)
    }

    private var activeStage: RepAttemptStage? {
        guard case .active(_, let topReachedAt) = cycle else { return nil }
        return .of(reachedEnd: topReachedAt != nil, zones: [tracker.lastZone ?? .bottom])
    }

    private func resetTracking() {
        tracker.reset()
        startConfirmedAt = nil
        cycle = .awaitingStart
        recentForearms = []
        recentUpperArms = []
        smoothedElbowY = nil
        locked = nil
        awayFromStartSince = nil
        lastThresholds = [:]
        formMonitor = Self.makeFormMonitor(configuration)
    }

    private func classify(signal: Double, elbowAngle: Double) -> MovementZone {
        if signal <= configuration.bottomMaxRatio, elbowAngle >= configuration.bottomMinElbowAngle { return .bottom }
        if signal >= configuration.topMinRatio { return .top }
        return .middle
    }

    /// Smooths elbow height and keeps the longest recent forearm as the live height ruler.
    private func liveReference(for arm: ArmPoints) -> Reference {
        recentForearms.append(arm.forearmLength)
        if recentForearms.count > configuration.rulerWindow {
            recentForearms.removeFirst(recentForearms.count - configuration.rulerWindow)
        }
        recentUpperArms.append(arm.upperArmLength)
        if recentUpperArms.count > configuration.rulerWindow {
            recentUpperArms.removeFirst(recentUpperArms.count - configuration.rulerWindow)
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

    /// The threshold lines extend forward past the wrist's path in the direction the person faces.
    private func makeThresholds(arm: ArmPoints, facing: CGFloat, reference: Reference) -> ArmThresholds {
        func line(signal: Double, label: String) -> ThresholdLine {
            let y = reference.elbowY - CGFloat(signal) * reference.ruler
            return ThresholdLine(from: CGPoint(x: arm.elbow.x - facing * 0.3 * reference.ruler, y: y),
                                 to: CGPoint(x: arm.elbow.x + facing * reference.ruler, y: y), label: label)
        }
        let confirmed: RepCheckpoint?
        switch tracker.confirmed {
        case .bottom: confirmed = .start
        case .top: confirmed = .top
        default: confirmed = nil
        }
        return ArmThresholds(startLine: line(signal: configuration.bottomMaxRatio, label: "Start ↓"),
                             topLine: line(signal: configuration.topMinRatio, label: "Top ↑"),
                             isLocked: locked != nil, confirmed: confirmed)
    }

    /// +1 when the person faces larger x; fall back to the wrist when the nose is outside the frame.
    private func facing(_ arm: ArmPoints, in frame: PoseFrame) -> CGFloat {
        if let nose = frame.point(.nose, minimumConfidence: configuration.minimumJointConfidence) {
            return nose.x >= arm.shoulder.x ? 1 : -1
        }
        return arm.wrist.x >= arm.elbow.x ? 1 : -1
    }

    private func sway(side: BodySide, arm: ArmPoints, upperArm: CGFloat, in frame: PoseFrame) -> CGVector? {
        guard let hip = frame.point(side.hip, minimumConfidence: configuration.minimumJointConfidence) else { return nil }
        return CGVector(dx: (arm.shoulder.x - hip.x) / upperArm, dy: (arm.shoulder.y - hip.y) / upperArm)
    }

    private static func makeFormMonitor(_ configuration: HammerCurlSideConfiguration) -> HammerCurlFormMonitor {
        HammerCurlFormMonitor(configuration: .standard, sideOn: true,
                              sideElbowDriftTolerance: configuration.elbowDriftTolerance,
                              sideSwayTolerance: configuration.swayTolerance)
    }
}
