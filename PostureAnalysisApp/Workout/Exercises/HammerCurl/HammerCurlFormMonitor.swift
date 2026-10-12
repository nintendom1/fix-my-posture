import CoreGraphics
import Foundation

/// Watches each arm's curl attempts for form cues. It only observes; counting never depends on it.
///
/// An attempt begins once an arm has settled hanging straight and its wrist rises `attemptMinimumRise`
/// above where it hung, and ends when the arm settles again. Each arm is judged on its own, so
/// alternating curls produce one attempt per arm. Elbow flare and body sway are measured against the
/// user's own stance at the start of the set.
struct HammerCurlFormMonitor {
    /// One arm on one frame.
    struct ArmSample {
        let ratio: Double
        let zone: MovementZone
        let confirmed: MovementZone?
        /// Sideways elbow distance from its shoulder, in shoulder widths; nil without both shoulders.
        let flare: Double?
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
        /// Lowest height since the arm last left the Top zone while still confirmed at the top.
        var lowestSinceTop: Double?
    }

    private let configuration: HammerCurlConfiguration
    private var attempts: [BodySide: Attempt] = [:]
    private var settledSamples: [BodySide: Int] = [:]
    private var lastPeaks: [BodySide: Double] = [:]
    private var lastBottoms: [BodySide: Double] = [:]
    private var flareBaseline: [BodySide: [Double]] = [:]
    private var swayBaseline: [CGVector] = []
    private var flareDeviation: Double?
    private var swayDeviation: Double?

    init(configuration: HammerCurlConfiguration) {
        self.configuration = configuration
    }

    mutating func update(at time: TimeInterval, arms: [BodySide: ArmSample], sway: CGVector?, counting: Bool) -> Output {
        var output = Output()
        let bothHanging = BodySide.allCases.allSatisfy { arms[$0]?.zone == .bottom && arms[$0]?.confirmed == .bottom }
        updateBaselines(arms, sway: sway, bothHanging: bothHanging)
        if counting {
            if let flareDeviation, flareDeviation > configuration.elbowFlareTolerance { output.signals.insert(.curlElbowsIn) }
            if let swayDeviation, swayDeviation > configuration.swayTolerance { output.signals.insert(.curlBodyStill) }
        }
        guard counting else {
            attempts = [:]
            settledSamples = [:]
            return output
        }

        for side in BodySide.allCases {
            guard let sample = arms[side] else { continue }
            let settled = sample.zone == .bottom && sample.confirmed == .bottom
            settledSamples[side] = settled ? (settledSamples[side] ?? 0) + 1 : 0
            if (settledSamples[side] ?? 0) >= configuration.confirmationSamples {
                var waiting = Attempt(startRatio: sample.ratio, peak: sample.ratio)
                if let previous = attempts[side] {
                    if previous.started {
                        output.repForms.append(finish(previous, side: side, at: time))
                    } else {
                        // Measure the rise from where the arm hung, not from where it began to lift.
                        waiting.startRatio = min(previous.startRatio, sample.ratio)
                    }
                }
                attempts[side] = waiting
                continue
            }
            guard var attempt = attempts[side] else { continue }
            attempt.peak = max(attempt.peak, sample.ratio)
            if sample.ratio >= attempt.startRatio + configuration.attemptMinimumRise { attempt.started = true }
            if sample.confirmed == .top {
                attempt.reachedTop = true
                // Still confirmed at the top means the arm hasn't hung straight since.
                if sample.zone == .top {
                    if let low = attempt.lowestSinceTop, attempt.peak - low >= configuration.returnDip {
                        output.repForms.append(RepForm(timestamp: time, flags: [.curlStraightenAtBottom]))
                    }
                    attempt.lowestSinceTop = nil
                } else {
                    attempt.lowestSinceTop = min(attempt.lowestSinceTop ?? sample.ratio, sample.ratio)
                }
            } else {
                attempt.lowestSinceTop = nil
            }
            attempts[side] = attempt
        }
        return output
    }

    /// A tracking gap on one arm: its attempt in progress can't be judged.
    mutating func invalidate(_ side: BodySide) {
        attempts[side] = nil
        settledSamples[side] = 0
    }

    /// The last attempt's highest and hanging heights per arm, plus live flare and sway drift.
    var readings: [FormReading] {
        func pair(_ values: [BodySide: Double]) -> String {
            guard !values.isEmpty else { return "–" }
            return BodySide.allCases.map { side in
                "\(side.shortLabel) " + (values[side].map { String(format: "%.2f", $0) } ?? "–")
            }.joined(separator: " ")
        }
        func format(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }
        return [
            FormReading(label: "↑", value: pair(lastPeaks)),
            FormReading(label: "↓", value: pair(lastBottoms)),
            FormReading(label: "flare", value: format(flareDeviation)),
            FormReading(label: "sway", value: format(swayDeviation))
        ]
    }

    // MARK: - Private

    private mutating func finish(_ attempt: Attempt, side: BodySide, at time: TimeInterval) -> RepForm {
        lastPeaks[side] = attempt.peak
        lastBottoms[side] = attempt.startRatio
        return RepForm(timestamp: time, flags: attempt.reachedTop ? [] : [.curlFullRange])
    }

    /// Baselines come from the first samples with both arms hanging; only drift from them is cued.
    private mutating func updateBaselines(_ arms: [BodySide: ArmSample], sway: CGVector?, bothHanging: Bool) {
        let needed = configuration.baselineSamples
        var deviations: [Double] = []
        for side in BodySide.allCases {
            guard let flare = arms[side]?.flare else { continue }
            var samples = flareBaseline[side] ?? []
            if bothHanging, samples.count < needed {
                samples.append(flare)
                flareBaseline[side] = samples
            }
            if samples.count >= needed, needed > 0 {
                deviations.append(flare - samples.reduce(0, +) / Double(samples.count))
            }
        }
        flareDeviation = deviations.max()

        guard let sway else {
            swayDeviation = nil
            return
        }
        if bothHanging, swayBaseline.count < needed { swayBaseline.append(sway) }
        guard swayBaseline.count >= needed, needed > 0 else {
            swayDeviation = nil
            return
        }
        let count = CGFloat(swayBaseline.count)
        let mean = CGVector(dx: swayBaseline.map(\.dx).reduce(0, +) / count, dy: swayBaseline.map(\.dy).reduce(0, +) / count)
        swayDeviation = Double(hypot(sway.dx - mean.dx, sway.dy - mean.dy))
    }
}
