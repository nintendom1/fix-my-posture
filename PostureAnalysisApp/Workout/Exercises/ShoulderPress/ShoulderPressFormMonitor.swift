import Foundation

extension CoachingCueID {
    static let pressFullExtension = CoachingCueID(rawValue: "press.full_extension")
    static let pressReturnToStart = CoachingCueID(rawValue: "press.return_to_start")
    static let pressControlledLowering = CoachingCueID(rawValue: "press.controlled_lowering")
    static let pressTorsoCentered = CoachingCueID(rawValue: "press.torso_centered")
    static let pressEvenArms = CoachingCueID(rawValue: "press.even_arms")
}

/// Watches shoulder-press attempts for form cues. It only observes; counting never depends on it.
///
/// Heights are the analyzer's own: wrist height above the locked shoulder in that arm's length, so every
/// reading is the same at any distance. Times where the wrist crosses the drawn Top and Start lines are
/// interpolated between samples, so they don't jump with the 10 Hz sampling.
///
/// An attempt begins once both arms have settled at the start and either wrist rises
/// `attemptMinimumRise` above it, and ends when both settle at the start again. Attempts that
/// didn't count (a half press) are reported too, so the coach can say why.
struct ShoulderPressFormMonitor {
    /// One arm on one complete frame.
    struct ArmSample {
        let height: Double
        let elbowAngle: Double
        let zone: MovementZone
        /// The arm's confirmed checkpoint after this frame.
        let confirmed: MovementZone?
    }

    struct Output {
        var repForms: [RepForm] = []
        var signals: Set<CoachingCueID> = []
    }

    private struct ArmAttempt {
        var startHeight: Double
        var peakHeight: Double
        var peakElbow: Double
        var reachedTop = false
        var topCrossUp: TimeInterval?
        var topCrossDown: TimeInterval?
        var startCrossDown: TimeInterval?
        /// Lowest height since the arm last left the Top zone while still confirmed at the top.
        var lowestSinceTop: Double?

        init(_ sample: ArmSample) {
            startHeight = sample.height
            peakHeight = sample.height
            peakElbow = sample.elbowAngle
        }
    }

    private struct Attempt {
        var arms: [BodySide: ArmAttempt]
        var started = false
        /// Largest left/right height difference before both wrists crossed the Top line.
        var maxHeightGap = 0.0
    }

    /// The last finished attempt, for the Show Measurements "Last rep" line.
    private struct Summary {
        var descent: TimeInterval?
        var timingGap: TimeInterval?
        var heightGap: Double
        var peakElbow: Double
    }

    private let configuration: ShoulderPressConfiguration
    /// Nil until both arms settle at the start.
    private var attempt: Attempt?
    private var previous: [BodySide: (time: TimeInterval, height: Double)] = [:]
    private var settledSamples = 0
    private var torsoBaselineSamples: [Double] = []
    private var torsoDeviation: Double?
    private var lastSummary: Summary?

    init(configuration: ShoulderPressConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, arms: [BodySide: ArmSample], torsoOffset: Double?,
                         counting: Bool) -> Output {
        var output = Output()
        let bothAtStart = BodySide.allCases.allSatisfy { arms[$0]?.zone == .bottom && arms[$0]?.confirmed == .bottom }
        settledSamples = bothAtStart ? settledSamples + 1 : 0

        updateTorso(torsoOffset, bothAtStart: bothAtStart)
        if counting, let torsoDeviation, abs(torsoDeviation) > configuration.torsoOffsetTolerance {
            output.signals.insert(.pressTorsoCentered)
        }

        guard counting else {
            attempt = nil
            previous = [:]
            return output
        }
        defer { previous = arms.mapValues { (time: time, height: $0.height) } }

        if settledSamples >= configuration.confirmationSamples {
            var waiting = Attempt(arms: arms.mapValues(ArmAttempt.init))
            if let previousAttempt = attempt {
                if previousAttempt.started {
                    output.repForms.append(finish(previousAttempt, at: time))
                } else {
                    // The rise is measured from where the arm rested, not from where it began to lift
                    // while still inside the Start zone.
                    for (side, arm) in previousAttempt.arms {
                        guard let current = waiting.arms[side]?.startHeight else { continue }
                        waiting.arms[side]?.startHeight = min(arm.startHeight, current)
                    }
                }
            }
            attempt = waiting
            return output
        }
        guard var current = attempt else { return output }

        var pressedAgain = false
        for side in BodySide.allCases {
            guard let sample = arms[side], var arm = current.arms[side] else { continue }
            let height = sample.height
            arm.peakHeight = max(arm.peakHeight, height)
            arm.peakElbow = max(arm.peakElbow, sample.elbowAngle)
            if height >= arm.startHeight + configuration.attemptMinimumRise { current.started = true }
            if sample.confirmed == .top { arm.reachedTop = true }

            if let last = previous[side] {
                let topLine = configuration.topMinHeight
                let startLine = configuration.bottomMaxHeight
                if arm.topCrossUp == nil, let t = Self.crossing(of: topLine, from: last, to: (time, height), upward: true) {
                    arm.topCrossUp = t
                }
                if let t = Self.crossing(of: topLine, from: last, to: (time, height), upward: false) {
                    arm.topCrossDown = t
                    arm.startCrossDown = nil
                }
                if arm.topCrossDown != nil, arm.startCrossDown == nil,
                   let t = Self.crossing(of: startLine, from: last, to: (time, height), upward: false) {
                    arm.startCrossDown = t
                }
            }

            // Still confirmed at the top means the arm hasn't returned to the start since.
            if sample.confirmed == .top {
                if sample.zone == .top {
                    if let low = arm.lowestSinceTop, arm.peakHeight - low >= configuration.returnDip { pressedAgain = true }
                    arm.lowestSinceTop = nil
                } else {
                    arm.lowestSinceTop = min(arm.lowestSinceTop ?? height, height)
                }
            } else {
                arm.lowestSinceTop = nil
            }
            current.arms[side] = arm
        }

        let crossedTop = current.arms.values.allSatisfy { $0.topCrossUp != nil }
        if !crossedTop, let left = arms[.left], let right = arms[.right] {
            current.maxHeightGap = max(current.maxHeightGap, abs(left.height - right.height))
        }
        if pressedAgain {
            output.repForms.append(RepForm(timestamp: time, flags: [.pressReturnToStart]))
        }
        attempt = current
        return output
    }

    /// A tracking gap: the attempt in progress can't be judged.
    mutating func invalidate() {
        attempt = nil
        previous = [:]
        settledSamples = 0
    }

    /// Labeled values for the last attempt, plus the live torso offset.
    var readings: [FormReading] {
        func format(_ value: Double?, _ pattern: String) -> String {
            value.map { String(format: pattern, $0) } ?? "–"
        }
        return [
            FormReading(label: "↓", value: format(lastSummary?.descent, "%.2fs")),
            FormReading(label: "Δt", value: format(lastSummary?.timingGap, "%.2fs")),
            FormReading(label: "Δh", value: format(lastSummary?.heightGap, "%.2f")),
            FormReading(label: "ext", value: format(lastSummary?.peakElbow, "%.0f°")),
            FormReading(label: "torso", value: format(torsoDeviation.map(abs), "%.2f"))
        ]
    }

    // MARK: - Private

    private mutating func finish(_ attempt: Attempt, at time: TimeInterval) -> RepForm {
        let arms = Array(attempt.arms.values)
        var flags: Set<CoachingCueID> = []

        let peakElbow = arms.map(\.peakElbow).min() ?? 0
        if !arms.allSatisfy(\.reachedTop) || peakElbow < configuration.fullExtensionElbowAngle {
            flags.insert(.pressFullExtension)
        }

        let descent = arms.compactMap { arm in
            arm.topCrossDown.flatMap { top in arm.startCrossDown.map { $0 - top } }
        }.min()
        if let descent, descent < configuration.minimumDescentTime {
            flags.insert(.pressControlledLowering)
        }

        let crossings = arms.compactMap(\.topCrossUp)
        let timingGap = crossings.count == arms.count ? (crossings.max() ?? 0) - (crossings.min() ?? 0) : nil
        if (timingGap ?? 0) > configuration.maximumTopTimingGap || attempt.maxHeightGap > configuration.maximumHeightGap {
            flags.insert(.pressEvenArms)
        }

        lastSummary = Summary(descent: descent, timingGap: timingGap, heightGap: attempt.maxHeightGap, peakElbow: peakElbow)
        return RepForm(timestamp: time, flags: flags)
    }

    /// The baseline is the user's own stance at the start of the set; only drift from it is cued.
    private mutating func updateTorso(_ offset: Double?, bothAtStart: Bool) {
        guard let offset else {
            torsoDeviation = nil
            return
        }
        let needed = configuration.torsoBaselineSamples
        if bothAtStart, torsoBaselineSamples.count < needed {
            torsoBaselineSamples.append(offset)
        }
        guard torsoBaselineSamples.count >= needed, needed > 0 else {
            torsoDeviation = nil
            return
        }
        torsoDeviation = offset - torsoBaselineSamples.reduce(0, +) / Double(torsoBaselineSamples.count)
    }

    /// Interpolated time at which height crosses `line` between two samples, if it does.
    private static func crossing(of line: Double, from a: (time: TimeInterval, height: Double),
                                 to b: (time: TimeInterval, height: Double), upward: Bool) -> TimeInterval? {
        let crosses = upward ? (a.height < line && b.height >= line) : (a.height >= line && b.height < line)
        guard crosses, b.height != a.height else { return nil }
        return a.time + (line - a.height) / (b.height - a.height) * (b.time - a.time)
    }
}
