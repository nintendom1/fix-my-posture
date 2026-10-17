import Foundation

/// The persisted rest behavior for future workout settings.
enum RestPolicy: Codable, Equatable {
    case exerciseDefault
    case fixed(seconds: Int)

    fileprivate var clamped: Self {
        switch self {
        case .exerciseDefault:
            return .exerciseDefault
        case .fixed(let seconds):
            return .fixed(seconds: min(max(seconds, 30), 120))
        }
    }
}

/// The display unit selected for workout weights.
enum PreferredWeightUnit: String, Codable, Equatable {
    case lb
    case kg
}

/// All UserDefaults keys are declared here so old keys remain stable and future ones stay namespaced.
enum PreferenceKey {
    static let cameraTiltCompensationEnabled = "cameraTiltCompensationEnabled"
    static let showHorizonLine = "showHorizonLine"
    static let feedbackRefreshRate = "feedbackRefreshRate"

    static let workoutCoachShowMeasurements = "workoutCoach.showMeasurements"
    static let workoutCoachCoachMuted = "workoutCoach.coachMuted"
    static let workoutCoachMicMuted = "workoutCoach.micMuted"
    static let workoutCoachVoiceTipSpoken = "workoutCoach.voiceTipSpoken"
    static func workoutCoachGuideSeen(_ exerciseID: String) -> String { "workoutCoach.guideSeen.\(exerciseID)" }
    static func workoutCoachTarget(_ exerciseID: String) -> String { "workoutCoach.target.\(exerciseID)" }

    /// New Phase 4 settings use the settings. namespace.
    static let restPolicy = "settings.restPolicy"
    static let weightUnit = "settings.weightUnit"

    /// New workout flow choices use the train. namespace.
    static let startByHolding = "train.startByHolding"
    static let upNextOverride = "train.upNextOverride"
}

/// The single typed boundary for the app's UserDefaults preferences.
protocol AppPreferencesStoring: AnyObject {
    var cameraTiltCompensationEnabled: Bool { get set }
    var showHorizonLine: Bool { get set }
    var feedbackRefreshRate: Int { get set }

    var workoutCoachShowMeasurements: Bool { get set }
    var workoutCoachCoachMuted: Bool { get set }
    var workoutCoachMicMuted: Bool { get set }
    var workoutCoachVoiceTipSpoken: Bool { get set }
    func guideSeen(for exerciseID: String) -> Bool
    func setGuideSeen(_ seen: Bool, for exerciseID: String)
    func exerciseTarget(for exerciseID: String) -> ExerciseTarget?
    func setExerciseTarget(_ target: ExerciseTarget?, for exerciseID: String)

    var restPolicy: RestPolicy { get set }
    var weightUnit: PreferredWeightUnit { get set }
    var startByHolding: Bool { get set }
    var upNextOverride: UUID? { get set }
}

/// UserDefaults-backed preferences. Existing keys and value formats are retained for upgrade compatibility.
final class UserDefaultsPreferences: AppPreferencesStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var cameraTiltCompensationEnabled: Bool {
        get { defaults.object(forKey: PreferenceKey.cameraTiltCompensationEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: PreferenceKey.cameraTiltCompensationEnabled) }
    }

    var showHorizonLine: Bool {
        get { defaults.object(forKey: PreferenceKey.showHorizonLine) as? Bool ?? true }
        set { defaults.set(newValue, forKey: PreferenceKey.showHorizonLine) }
    }

    var feedbackRefreshRate: Int {
        get { defaults.object(forKey: PreferenceKey.feedbackRefreshRate) as? Int ?? 5 }
        set { defaults.set(newValue, forKey: PreferenceKey.feedbackRefreshRate) }
    }

    var workoutCoachShowMeasurements: Bool {
        get { defaults.bool(forKey: PreferenceKey.workoutCoachShowMeasurements) }
        set { defaults.set(newValue, forKey: PreferenceKey.workoutCoachShowMeasurements) }
    }

    var workoutCoachCoachMuted: Bool {
        get { defaults.bool(forKey: PreferenceKey.workoutCoachCoachMuted) }
        set { defaults.set(newValue, forKey: PreferenceKey.workoutCoachCoachMuted) }
    }

    var workoutCoachMicMuted: Bool {
        get { defaults.bool(forKey: PreferenceKey.workoutCoachMicMuted) }
        set { defaults.set(newValue, forKey: PreferenceKey.workoutCoachMicMuted) }
    }

    var workoutCoachVoiceTipSpoken: Bool {
        get { defaults.bool(forKey: PreferenceKey.workoutCoachVoiceTipSpoken) }
        set { defaults.set(newValue, forKey: PreferenceKey.workoutCoachVoiceTipSpoken) }
    }

    func guideSeen(for exerciseID: String) -> Bool {
        defaults.bool(forKey: PreferenceKey.workoutCoachGuideSeen(exerciseID))
    }

    func setGuideSeen(_ seen: Bool, for exerciseID: String) {
        defaults.set(seen, forKey: PreferenceKey.workoutCoachGuideSeen(exerciseID))
    }

    func exerciseTarget(for exerciseID: String) -> ExerciseTarget? {
        defaults.data(forKey: PreferenceKey.workoutCoachTarget(exerciseID))
            .flatMap { try? JSONDecoder().decode(ExerciseTarget.self, from: $0) }
    }

    func setExerciseTarget(_ target: ExerciseTarget?, for exerciseID: String) {
        let key = PreferenceKey.workoutCoachTarget(exerciseID)
        guard let target, let data = try? JSONEncoder().encode(target) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    var restPolicy: RestPolicy {
        get {
            guard let data = defaults.data(forKey: PreferenceKey.restPolicy),
                  let value = try? JSONDecoder().decode(RestPolicy.self, from: data) else {
                return .exerciseDefault
            }
            return value.clamped
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue.clamped) else { return }
            defaults.set(data, forKey: PreferenceKey.restPolicy)
        }
    }

    var weightUnit: PreferredWeightUnit {
        get { defaults.string(forKey: PreferenceKey.weightUnit).flatMap(PreferredWeightUnit.init(rawValue:)) ?? .lb }
        set { defaults.set(newValue.rawValue, forKey: PreferenceKey.weightUnit) }
    }

    var startByHolding: Bool {
        get { defaults.object(forKey: PreferenceKey.startByHolding) as? Bool ?? true }
        set { defaults.set(newValue, forKey: PreferenceKey.startByHolding) }
    }

    var upNextOverride: UUID? {
        get { defaults.string(forKey: PreferenceKey.upNextOverride).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: PreferenceKey.upNextOverride)
            } else {
                defaults.removeObject(forKey: PreferenceKey.upNextOverride)
            }
        }
    }
}

/// Isolated in-memory preferences for tests, previews, and deterministic model construction.
final class InMemoryPreferences: AppPreferencesStoring {
    var cameraTiltCompensationEnabled = true
    var showHorizonLine = true
    var feedbackRefreshRate = 5

    var workoutCoachShowMeasurements = false
    var workoutCoachCoachMuted = false
    var workoutCoachMicMuted = false
    var workoutCoachVoiceTipSpoken = false
    private var seenGuides = Set<String>()
    private var exerciseTargets: [String: ExerciseTarget] = [:]

    private var storedRestPolicy: RestPolicy = .exerciseDefault
    var restPolicy: RestPolicy {
        get { storedRestPolicy }
        set { storedRestPolicy = newValue.clamped }
    }

    var weightUnit: PreferredWeightUnit = .lb
    var startByHolding = true
    var upNextOverride: UUID?

    func guideSeen(for exerciseID: String) -> Bool {
        seenGuides.contains(exerciseID)
    }

    func setGuideSeen(_ seen: Bool, for exerciseID: String) {
        if seen {
            seenGuides.insert(exerciseID)
        } else {
            seenGuides.remove(exerciseID)
        }
    }

    func exerciseTarget(for exerciseID: String) -> ExerciseTarget? {
        exerciseTargets[exerciseID]
    }

    func setExerciseTarget(_ target: ExerciseTarget?, for exerciseID: String) {
        exerciseTargets[exerciseID] = target
    }
}
