import Foundation

/// Counts two-arm presses from the front: both arms must reach the top within one cycle and
/// both must return to the bottom. Each arm has its own hysteresis tracker.
final class ShoulderPressAnalyzer: ExerciseAnalyzing {
    let epoch: Int
    private let configuration: ShoulderPressConfiguration
    private var trackers: [BodySide: HysteresisPhaseTracker]
    private var cycle: Cycle = .awaitingBottom
    private var lastCompleteSample: TimeInterval?

    private enum Cycle {
        /// Both arms must confirm the bottom before a rep can begin.
        case awaitingBottom
        case active(ActiveCycle)
    }

    private struct ActiveCycle {
        /// Last time both arms sat at the bottom before any arm reached the top.
        var movementStart: TimeInterval
        var reachedTop: Set<BodySide> = []
    }

    init(epoch: Int, configuration: ShoulderPressConfiguration = .standard) {
        self.epoch = epoch
        self.configuration = configuration
        let tracker = HysteresisPhaseTracker(requiredSamples: configuration.confirmationSamples)
        trackers = [.left: tracker, .right: tracker]
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        let confidence = configuration.minimumJointConfidence
        guard let torso = ArmGeometry.torso(in: frame, minimumConfidence: confidence), torso.length > 1,
              let left = ArmGeometry.arm(.left, in: frame, minimumConfidence: confidence),
              let right = ArmGeometry.arm(.right, in: frame, minimumConfidence: confidence) else {
            // Trackers hold; the gap check below decides whether the cycle survives.
            return ExerciseAnalysis()
        }

        let time = frame.timestamp
        if let last = lastCompleteSample, time - last > configuration.maximumSampleGap {
            invalidateCycle()
        }
        lastCompleteSample = time

        var zones: [BodySide: MovementZone] = [:]
        var newlyConfirmed: [BodySide: MovementZone] = [:]
        for (side, arm) in [(BodySide.left, left), (.right, right)] {
            let heightRatio = Double(arm.shoulder.y - arm.wrist.y) / Double(torso.length)
            let zone = classify(heightRatio: heightRatio, elbowAngle: arm.elbowAngle)
            zones[side] = zone
            if let confirmed = trackers[side]?.update(zone) { newlyConfirmed[side] = confirmed }
        }

        var analysis = ExerciseAnalysis()
        analysis.endPositionSides = Set(BodySide.allCases.filter { trackers[$0]?.confirmed == .top })

        guard counting else {
            cycle = .awaitingBottom
            return analysis
        }

        let bothConfirmedBottom = BodySide.allCases.allSatisfy { trackers[$0]?.confirmed == .bottom }
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
                if active.reachedTop.count == BodySide.allCases.count,
                   time - active.movementStart >= configuration.minimumRepDuration {
                    analysis.repEvents.append(RepEvent(epoch: epoch, timestamp: time, sides: Set(BodySide.allCases)))
                }
                active = ActiveCycle(movementStart: time)
            }
            cycle = .active(active)
        }
        return analysis
    }

    private func classify(heightRatio: Double, elbowAngle: Double) -> MovementZone {
        if heightRatio <= configuration.bottomMaxHeightRatio, elbowAngle <= configuration.bottomMaxElbowAngle {
            return .bottom
        }
        if heightRatio >= configuration.topMinHeightRatio, elbowAngle >= configuration.topMinElbowAngle {
            return .top
        }
        return .middle
    }

    private func invalidateCycle() {
        cycle = .awaitingBottom
        for side in BodySide.allCases { trackers[side]?.reset() }
    }
}
