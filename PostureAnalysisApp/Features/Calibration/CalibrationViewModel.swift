import AdaptiveTraining
import Foundation
import Observation

/// Every word the calibration shows, in one place so the tone stays warm and plain. Finding a starting point is never
/// a test, a score, or a label, and the copy never uses medical words. `CalibrationViewModelTests` scans these strings.
enum CalibrationCopy {
    static let title = "Find a starting point"
    static let intro = "Let's find a comfortable starting point. A few tiny samples, no tests."
    static let close = "Close"
    static let continueButton = "Continue"

    static let equipmentTitle = "What do you have at home?"
    static let equipmentDetail = "Both are optional. Skip them if you like."
    static let dumbbells = "Dumbbells"
    static let band = "A resistance band"

    static let areasTitle = "Where would you like to start?"
    static let areasDetail = "Push and squat are a gentle place to begin. Add more if you like."
    static let areasNeedOne = "Pick at least one to continue."

    static let closenessTitle = "Which feels closest to what you can do comfortably today?"
    static let closenessNote = "We'll begin gently and work up from there."
    static let notSure = "Not sure"
    static let notSureDetail = "We'll begin with the gentlest one."
    static let skipArea = "Skip this area"

    static let sampleTitle = "A tiny sample"
    static let sampleDetail = "Go gently. Afterwards you'll tell us how it felt."
    static let startSample = "Start sample"
    static let harderTitle = "That felt easy. Want to try a slightly harder one?"
    static let harderDetail = "Skipping it is fine. We'll start from what you just did."
    static let tryHarder = "Try it"
    static let stayHere = "No, stay here"

    static let noRating = "That sample didn't get a rating, so nothing changed. You can try it again or skip this area."
    static let sampleUnavailable = "That sample can't run on this device yet. You can skip this area."
    static let saveFailed = "We couldn't save your starting points. Please try again."

    static let summaryTitle = "Your starting points"
    static let summaryDetail = "Today's Session begins from these."
    static let summaryEmpty = "No starting points yet."
    static let useThese = "Use these"
    static let leaveWithoutSaving = "Leave without saving"

    static let doneTitle = "You're all set"
    static let doneDetail = "Today's Session will begin from these starting points."
    static let done = "Done"

    static let leaveTitle = "Leave without saving?"
    static let leaveDetail = "Nothing changes if you leave now."
    static let leave = "Leave"
    static let keepGoing = "Keep going"

    static let couldNotStart = "We couldn't start this just now."
    static let unavailable = "Finding a starting point isn't available right now."

    /// Every fixed string above, for the copy scan.
    static let all: [String] = [
        title, intro, close, continueButton, equipmentTitle, equipmentDetail, dumbbells, band, areasTitle, areasDetail,
        areasNeedOne, closenessTitle, closenessNote, notSure, notSureDetail, skipArea, sampleTitle, sampleDetail,
        startSample, harderTitle, harderDetail, tryHarder, stayHere, noRating, sampleUnavailable, saveFailed,
        summaryTitle, summaryDetail, summaryEmpty, useThese, leaveWithoutSaving, doneTitle, doneDetail, done,
        leaveTitle, leaveDetail, leave, keepGoing, couldNotStart, unavailable
    ]

    static func equipmentName(_ equipment: TrainingEquipment) -> String {
        switch equipment {
        case .dumbbells: return dumbbells
        case .band: return band
        }
    }

    /// The plain name of a movement area.
    static func areaName(_ family: MovementFamilyID) -> String {
        switch family {
        case .push: return "Push"
        case .squat: return "Squat"
        case .row: return "Row"
        case .overhead: return "Overhead"
        case .hinge: return "Hinge"
        case .glute: return "Glutes"
        case .lunge: return "Lunge"
        case .neck: return "Neck"
        case .core: return "Core"
        default: return family.rawValue.capitalized
        }
    }

    /// One short line about what the area is.
    static func areaDetail(_ family: MovementFamilyID) -> String {
        switch family {
        case .push: return "Pressing away from you"
        case .squat: return "Sitting down and standing up"
        case .row: return "Drawing your shoulder blades together"
        case .overhead: return "Reaching and pressing overhead"
        case .hinge: return "Bending forward from the hips"
        case .glute: return "Squeezing through the hips"
        case .lunge: return "Shifting your weight from foot to foot"
        case .neck: return "Gentle chin tucks"
        case .core: return "Bracing through your middle"
        default: return ""
        }
    }

    /// "Push: Wall Push-Up × 3", or "Glutes: Glute Squeeze for 10 s" for a hold.
    static func summaryLine(area: String, exercise: String, dose: Dose) -> String {
        switch dose.kind {
        case .reps: return "\(area): \(exercise) × \(dose.amount)"
        case .seconds: return "\(area): \(exercise) for \(dose.amount) s"
        }
    }

    /// "2 reps" or "5 s".
    static func doseText(_ dose: Dose) -> String { dose.description }
}

/// The state of the calibration screen. The package's `CalibrationFlow` decides every step; this shows the step,
/// passes the answers back, runs each sample in the coach, and reports what happened. Leaving at any point records an
/// abandoned calibration and changes nothing.
@MainActor
@Observable
final class CalibrationViewModel {
    /// How the screen ended.
    enum Outcome: Equatable {
        case committed
        case left
    }

    struct Option: Equatable, Identifiable {
        let variant: VariantID
        let name: String
        var id: VariantID { variant }
    }

    struct SummaryLine: Equatable, Identifiable {
        let family: MovementFamilyID
        let text: String
        var id: MovementFamilyID { family }
    }

    /// What the sample on screen asks for, in words.
    struct SampleInfo: Equatable {
        let family: MovementFamilyID
        let area: String
        let exercise: String
        let amount: String
        let isHarderOffer: Bool
    }

    private(set) var flow: CalibrationFlow?
    /// The sample running in the coach, while the coach is up.
    private(set) var probeLaunch: CalibrationProbeLaunch?
    private(set) var notice: String?
    private(set) var outcome: Outcome?
    private(set) var isConfirmingExit = false
    private(set) var couldNotStart = false
    private(set) var selectedEquipment: Set<TrainingEquipment> = []
    private(set) var selectedFamilies: Set<MovementFamilyID> = []
    /// A sample has been started, so leaving asks first.
    private(set) var hasStartedSample = false

    @ObservationIgnored private let coordinator: any CalibrationCoordinating
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let onFinish: @MainActor () -> Void

    init(coordinator: any CalibrationCoordinating, now: @escaping () -> Date = Date.init,
         onFinish: @escaping @MainActor () -> Void = {}) {
        self.coordinator = coordinator
        self.now = now
        self.onFinish = onFinish
    }

    // MARK: - Reading

    var step: CalibrationStep? { flow?.step }

    /// Samples were started or rated, so leaving asks before it abandons the attempt.
    var hasDoneSamples: Bool { hasStartedSample || (flow?.probeCount ?? 0) > 0 }

    /// The areas the quiz offers, in catalog order.
    var offeredFamilies: [MovementFamilyID] { flow?.offeredFamilies ?? [] }

    var canContinueFromAreas: Bool { !selectedFamilies.isEmpty }

    /// The rungs for the closeness question, as plain names, easiest first.
    var closenessOptions: [Option] {
        guard case .closeness(_, let options)? = step else { return [] }
        return options.map { Option(variant: $0, name: coordinator.displayName(of: $0)) }
    }

    var closenessArea: MovementFamilyID? {
        guard case .closeness(let family, _)? = step else { return nil }
        return family
    }

    var sample: SampleInfo? {
        guard case .probe(let family, let rungDose, let isHarderOffer)? = step else { return nil }
        return SampleInfo(family: family, area: CalibrationCopy.areaName(family),
                          exercise: coordinator.displayName(of: rungDose.variant),
                          amount: CalibrationCopy.doseText(rungDose.dose), isHarderOffer: isHarderOffer)
    }

    var summaryLines: [SummaryLine] {
        guard case .summary(let points)? = step else { return [] }
        return points.map {
            SummaryLine(family: $0.family,
                        text: CalibrationCopy.summaryLine(area: CalibrationCopy.areaName($0.family),
                                                          exercise: coordinator.displayName(of: $0.start.variant),
                                                          dose: $0.start.dose))
        }
    }

    // MARK: - Starting

    /// Starts the attempt and saves it as in progress. Does nothing once started or ended.
    func begin() {
        guard flow == nil, outcome == nil, !couldNotStart else { return }
        guard let started = coordinator.startCalibration(asOf: now()) else {
            couldNotStart = true
            return
        }
        flow = started
        selectedFamilies = Set(started.suggestedFamilies)
    }

    // MARK: - The quiz

    func toggleEquipment(_ equipment: TrainingEquipment) {
        if !selectedEquipment.insert(equipment).inserted { selectedEquipment.remove(equipment) }
    }

    func continueFromEquipment() {
        guard var current = flow, case .equipment = current.step else { return }
        current.setEquipment(selectedEquipment)
        selectedFamilies = Set(current.suggestedFamilies)
        advance(to: current, saving: true)
    }

    func toggleFamily(_ family: MovementFamilyID) {
        guard offeredFamilies.contains(family) else { return }
        if !selectedFamilies.insert(family).inserted { selectedFamilies.remove(family) }
    }

    func continueFromAreas() {
        guard var current = flow, case .families = current.step, canContinueFromAreas else { return }
        current.setFamilies(Array(selectedFamilies))
        advance(to: current, saving: true)
    }

    /// Answers "Which feels closest?". `nil` is "Not sure".
    func answerCloseness(_ variant: VariantID?) {
        guard var current = flow, case .closeness(let family, _) = current.step else { return }
        current.answerCloseness(family: family, variant: variant)
        advance(to: current, saving: false)
    }

    // MARK: - Samples

    /// Prepares the sample on screen and opens it in the coach.
    func startSample() {
        guard let current = flow, case .probe = current.step, probeLaunch == nil else { return }
        notice = nil
        guard let launch = coordinator.prepareProbe(for: current, asOf: now(), onResult: { [weak self] result in
            self?.receive(result)
        }) else {
            notice = CalibrationCopy.sampleUnavailable
            return
        }
        hasStartedSample = true
        probeLaunch = launch
    }

    /// The coach recorded the sample's evidence. A rating goes to the flow, which decides what comes next; a sample
    /// nobody rated changes nothing and is offered again.
    func receive(_ result: CalibrationProbeResult) {
        guard let launch = probeLaunch, launch.id == result.launchID, var current = flow,
              case .probe(let family, let rungDose, _) = current.step, family == launch.family else { return }
        probeLaunch = nil
        guard let effort = result.effort else {
            notice = CalibrationCopy.noRating
            return
        }
        current.probeResult(family: family, effort: effort,
                            confirmed: result.confirmed ?? WorkAmount(kind: rungDose.dose.kind, amount: 0))
        advance(to: current, saving: false)
    }

    /// The coach was closed before the sample was rated. Nothing was decided.
    func sampleClosed() {
        probeLaunch = nil
    }

    /// Declining a harder sample means "stop here". It is neutral.
    func declineHarderSample() {
        guard var current = flow, case .probe(let family, _, true) = current.step else { return }
        current.declineHarderProbe(family: family)
        advance(to: current, saving: false)
    }

    /// Leaves the area being asked about out of the starting points.
    func skipArea() {
        guard var current = flow, probeLaunch == nil else { return }
        let family: MovementFamilyID
        switch current.step {
        case .closeness(let asked, _): family = asked
        case .probe(let sampled, _, _): family = sampled
        default: return
        }
        current.skipFamily(family: family)
        advance(to: current, saving: true)
    }

    // MARK: - Summary and exit

    /// Accepts the summary. Only now do the starting points change recommendations.
    func useThese() {
        guard let current = flow, case .summary(let points) = current.step, !points.isEmpty, outcome == nil else { return }
        guard coordinator.commitCalibration(current, asOf: now()) else {
            notice = CalibrationCopy.saveFailed
            return
        }
        notice = nil
        outcome = .committed
    }

    /// The close button. Asks first only when samples were done.
    func requestExit() {
        if outcome != nil {
            onFinish()
        } else if hasDoneSamples {
            isConfirmingExit = true
        } else {
            leave()
        }
    }

    func keepGoing() {
        isConfirmingExit = false
    }

    func confirmLeave() {
        isConfirmingExit = false
        leave()
    }

    /// Records an abandoned calibration, which changes nothing, and closes the screen.
    func leave() {
        guard outcome == nil else {
            onFinish()
            return
        }
        if let flow { coordinator.abandonCalibration(flow, asOf: now()) }
        probeLaunch = nil
        outcome = .left
        onFinish()
    }

    /// The Done button after the starting points were saved.
    func finish() {
        onFinish()
    }

    // MARK: - Helpers

    private func advance(to next: CalibrationFlow, saving: Bool) {
        flow = next
        notice = nil
        if saving { coordinator.saveCalibrationProgress(next) }
    }
}
