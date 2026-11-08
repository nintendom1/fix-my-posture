import Foundation
import CoreGraphics
@testable import PostureAnalysisApp

/// The author who supplied a scenario plan.
enum MovementAuthor: String, Codable, CaseIterable {
    case agent
    case developer
}

/// The behavior area a scenario is intended to exercise.
enum MovementCategory: String, Codable, CaseIterable {
    case canonical
    case depthROM = "depth_rom"
    case alignment
    case timing
    case tracking
    case sessionFraming = "session_framing"
}

/// How the generator handles impossible landmark edits.
enum MovementMode: String, Codable, CaseIterable {
    case constrained
    case raw
}

/// A problem found while validating an in-memory plan or scenario.
struct MovementValidationIssue: Codable, Equatable {
    let path: String
    let message: String

    init(_ path: String, _ message: String) {
        self.path = path
        self.message = message
    }
}

/// Errors that callers can inspect when decoding a versioned plan.
enum MovementScenarioSchemaError: Error, Equatable {
    case unknownSchemaVersion(Int)
    case unknownMutationKind(String)
    case unknownAssertionKind(String)
    case invalidSeedRepresentation(String)
    case invalidPlan([MovementValidationIssue])
}

/// A versioned collection of synthetic movement scenarios.
struct MovementPlan: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var title: String
    var purpose: String
    var author: MovementAuthor
    /// Caller-supplied ISO 8601 text. Generation never invents a creation date.
    var createdAt: String
    var scenarios: [MovementScenario]

    init(schemaVersion: Int = Self.currentSchemaVersion, id: String, title: String, purpose: String,
         author: MovementAuthor, createdAt: String, scenarios: [MovementScenario]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.purpose = purpose
        self.author = author
        self.createdAt = createdAt
        self.scenarios = scenarios
    }

    func validate() -> [MovementValidationIssue] {
        var issues: [MovementValidationIssue] = []
        if schemaVersion != Self.currentSchemaVersion {
            issues.append(.init("schemaVersion", "must be \(Self.currentSchemaVersion)"))
        }
        if !MovementValidation.isValidID(id) {
            issues.append(.init("id", "must use 1–64 lowercase ASCII letters, digits, '_' or '-'"))
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init("title", "must not be empty"))
        }
        if purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init("purpose", "must not be empty"))
        }
        if MovementISO8601.date(from: createdAt) == nil {
            issues.append(.init("createdAt", "must be an ISO 8601 date-time with a time-zone offset"))
        }
        if scenarios.count > 200 {
            issues.append(.init("scenarios", "must contain no more than 200 scenarios"))
        }
        var seenIDs = Set<String>()
        for (index, scenario) in scenarios.enumerated() {
            let prefix = "scenarios[\(index)]"
            if !seenIDs.insert(scenario.id).inserted {
                issues.append(.init("\(prefix).id", "duplicates scenario id \(scenario.id)"))
            }
            issues += scenario.validate(path: prefix)
        }
        return issues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw MovementScenarioSchemaError.unknownSchemaVersion(version)
        }
        schemaVersion = version
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        purpose = try container.decode(String.self, forKey: .purpose)
        author = try container.decode(MovementAuthor.self, forKey: .author)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        scenarios = try container.decode([MovementScenario].self, forKey: .scenarios)
        let problems = validate()
        guard problems.isEmpty else { throw MovementScenarioSchemaError.invalidPlan(problems) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(author, forKey: .author)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(scenarios, forKey: .scenarios)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, purpose, author, createdAt, scenarios
    }
}

/// A reproducible movement request with frozen assertions and explicit revision lineage.
struct MovementScenario: Codable, Equatable, Identifiable {
    var id: String
    var exercise: ExerciseID
    var category: MovementCategory
    var purpose: String
    var canonicalRevision: String
    var seed: UInt64
    var reps: Int
    var mode: MovementMode
    var mutations: [MovementMutation]
    var assertions: [MovementAssertion]
    var revision: Int
    var parentRevision: Int?

    static let maximumReps = 120

    init(id: String, exercise: ExerciseID, category: MovementCategory, purpose: String,
         canonicalRevision: String, seed: UInt64, reps: Int, mode: MovementMode,
         mutations: [MovementMutation], assertions: [MovementAssertion], revision: Int = 1,
         parentRevision: Int? = nil) {
        self.id = id
        self.exercise = exercise
        self.category = category
        self.purpose = purpose
        self.canonicalRevision = canonicalRevision
        self.seed = seed
        self.reps = reps
        self.mode = mode
        self.mutations = mutations
        self.assertions = assertions
        self.revision = revision
        self.parentRevision = parentRevision
    }

    private enum CodingKeys: String, CodingKey {
        case id, exercise, category, purpose, canonicalRevision, seed, reps, mode
        case mutations, assertions, revision, parentRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        exercise = ExerciseID(rawValue: try container.decode(String.self, forKey: .exercise))
        category = try container.decode(MovementCategory.self, forKey: .category)
        purpose = try container.decode(String.self, forKey: .purpose)
        canonicalRevision = try container.decode(String.self, forKey: .canonicalRevision)
        let seedText = try container.decode(String.self, forKey: .seed)
        guard !seedText.isEmpty, seedText.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let decodedSeed = UInt64(seedText) else {
            throw MovementScenarioSchemaError.invalidSeedRepresentation(seedText)
        }
        seed = decodedSeed
        reps = try container.decode(Int.self, forKey: .reps)
        mode = try container.decode(MovementMode.self, forKey: .mode)
        mutations = try container.decode([MovementMutation].self, forKey: .mutations)
        assertions = try container.decode([MovementAssertion].self, forKey: .assertions)
        revision = try container.decode(Int.self, forKey: .revision)
        parentRevision = try container.decodeIfPresent(Int.self, forKey: .parentRevision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exercise.rawValue, forKey: .exercise)
        try container.encode(category, forKey: .category)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(canonicalRevision, forKey: .canonicalRevision)
        try container.encode(String(seed), forKey: .seed)
        try container.encode(reps, forKey: .reps)
        try container.encode(mode, forKey: .mode)
        try container.encode(mutations, forKey: .mutations)
        try container.encode(assertions, forKey: .assertions)
        try container.encode(revision, forKey: .revision)
        try container.encodeIfPresent(parentRevision, forKey: .parentRevision)
    }

    func validate(path: String = "scenario") -> [MovementValidationIssue] {
        var issues: [MovementValidationIssue] = []
        if !MovementValidation.isValidID(id) {
            issues.append(.init("\(path).id", "must use 1–64 lowercase ASCII letters, digits, '_' or '-'"))
        }
        if !ExerciseCatalog.all.contains(where: { $0.id == exercise }) {
            issues.append(.init("\(path).exercise", "is not a registered exercise id"))
        }
        if purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init("\(path).purpose", "must not be empty"))
        }
        if canonicalRevision.isEmpty {
            issues.append(.init("\(path).canonicalRevision", "must not be empty"))
        }
        if reps < 1 {
            issues.append(.init("\(path).reps", "must be at least 1"))
        } else if reps > Self.maximumReps {
            issues.append(.init("\(path).reps", "must not exceed \(Self.maximumReps)"))
        }
        if revision < 1 {
            issues.append(.init("\(path).revision", "must be at least 1"))
        }
        if let parentRevision, parentRevision < 1 || parentRevision >= revision {
            issues.append(.init("\(path).parentRevision", "must be positive and earlier than revision"))
        }

        let sequenceDurations = MovementScenario.timelineDurations(reps: reps, exercise: exercise,
                                                                     mutations: mutations)
        let sequenceDuration = sequenceDurations?.output
        if (1...Self.maximumReps).contains(reps),
           ExerciseCatalog.all.contains(where: { $0.id == exercise }), sequenceDurations == nil {
            issues.append(.init(path, "tempo-scaled sequence duration must remain finite and positive"))
        }
        if let sequenceDuration {
            if !sequenceDuration.isFinite || sequenceDuration > 120 {
                issues.append(.init("\(path)", "sequence duration must be no more than 120 seconds"))
            }
        }
        for (index, mutation) in mutations.enumerated() {
            issues += mutation.validate(path: "\(path).mutations[\(index)]", reps: reps,
                                        sequenceDuration: sequenceDuration,
                                        pauseClockDuration: sequenceDurations?.prePause)
        }
        for (index, assertion) in assertions.enumerated() {
            issues += assertion.validate(path: "\(path).assertions[\(index)]")
        }
        return issues
    }

    /// Total output duration after per-rep tempo changes and pauses.
    static func sequenceDuration(reps: Int, exercise: ExerciseID,
                                 mutations: [MovementMutation]) -> TimeInterval? {
        timelineDurations(reps: reps, exercise: exercise, mutations: mutations)?.output
    }

    static func timelineDurations(reps: Int, exercise: ExerciseID,
                                  mutations: [MovementMutation]) -> MovementSequenceDurations? {
        guard reps > 0, reps <= Self.maximumReps,
              let definition = ExerciseCatalog.all.first(where: { $0.id == exercise }) else { return nil }
        return MovementSequenceDurations.calculate(reps: reps, motionDuration: definition.guide.motion.duration,
                                                    mutations: mutations)
    }
}

struct MovementSequenceDurations {
    static let readyHold: TimeInterval = 1.5
    private static let ticksPerSecond = 1_000_000_000.0

    /// Sequence duration on the tempo-scaled clock before pause insertions.
    let prePause: TimeInterval
    /// Sequence duration after pause insertions.
    let output: TimeInterval

    static func calculate(reps: Int, motionDuration: TimeInterval,
                          mutations: [MovementMutation]) -> MovementSequenceDurations? {
        guard (1...MovementScenario.maximumReps).contains(reps),
              motionDuration.isFinite, motionDuration > 0,
              let pauses = pauseSegments(in: mutations) else { return nil }

        var cursor = readyHold
        for rep in 1...reps {
            guard let duration = repetitionDuration(for: rep, motionDuration: motionDuration,
                                                    mutations: mutations),
                  let next = adding(duration, to: cursor) else { return nil }
            cursor = next
        }
        let prePause = cursor
        var output = prePause
        for pause in pauses {
            guard let next = adding(pause.duration, to: output) else { return nil }
            output = next
        }
        return MovementSequenceDurations(prePause: prePause, output: output)
    }

    static func repetitionDuration(for rep: Int, motionDuration: TimeInterval,
                                   mutations: [MovementMutation]) -> TimeInterval? {
        guard motionDuration.isFinite, motionDuration > 0,
              let scale = tempoScale(for: rep, mutations: mutations) else { return nil }
        return normalized(motionDuration * scale)
    }

    static func adding(_ duration: TimeInterval, to accumulated: TimeInterval) -> TimeInterval? {
        normalized(accumulated + duration)
    }

    /// Composite tempos are applied in mutation order for both validation and materialization.
    static func tempoScale(for rep: Int, mutations: [MovementMutation]) -> Double? {
        guard rep > 0 else { return nil }
        var product = 1.0
        for mutation in mutations {
            guard case .tempo(let scale, let reps) = mutation,
                  reps == nil || reps?.contains(rep) == true else { continue }
            product *= scale
            guard product.isFinite, product > 0 else { return nil }
        }
        return product
    }

    static func pauseSegments(in mutations: [MovementMutation]) -> [(at: TimeInterval, duration: TimeInterval)]? {
        let pauses = mutations.compactMap { mutation -> (at: TimeInterval, duration: TimeInterval)? in
            guard case .pause(let at, let duration) = mutation else { return nil }
            return (at, duration)
        }
        guard pauses.allSatisfy({ $0.at.isFinite && $0.duration.isFinite && $0.duration >= 0 }) else {
            return nil
        }
        return pauses.sorted {
            if $0.at == $1.at { return $0.duration < $1.duration }
            return $0.at < $1.at
        }
    }

    private static func normalized(_ value: TimeInterval) -> TimeInterval? {
        guard value.isFinite else { return nil }
        let scaled = value * ticksPerSecond
        guard scaled.isFinite else { return nil }
        let result = scaled.rounded() / ticksPerSecond
        return result.isFinite ? result : nil
    }
}

/// A typed pose or timing change applied while a scenario is materialized.
enum MovementMutation: Codable, Equatable {
    case jointOffset(joints: [String], dx: Double, dy: Double, peak: TimeInterval,
                     rise: TimeInterval, fall: TimeInterval, strength: Double)
    case depthScale(scale: Double, reps: [Int]?)
    case asymmetry(side: BodySide, amount: Double)
    case tempo(scale: Double, reps: [Int]?)
    case pause(at: TimeInterval, duration: TimeInterval)
    case frameGap(at: TimeInterval, duration: TimeInterval)
    case dropout(joints: [String], from: TimeInterval, to: TimeInterval)
    case confidence(joints: [String], from: TimeInterval, to: TimeInterval, value: Double)
    case framing(scale: Double, offsetX: Double, offsetY: Double)

    var kind: String {
        switch self {
        case .jointOffset: return "jointOffset"
        case .depthScale: return "depthScale"
        case .asymmetry: return "asymmetry"
        case .tempo: return "tempo"
        case .pause: return "pause"
        case .frameGap: return "frameGap"
        case .dropout: return "dropout"
        case .confidence: return "confidence"
        case .framing: return "framing"
        }
    }

    static func == (lhs: MovementMutation, rhs: MovementMutation) -> Bool {
        switch (lhs, rhs) {
        case let (.jointOffset(leftJoints, leftDX, leftDY, leftPeak, leftRise, leftFall, leftStrength),
                  .jointOffset(rightJoints, rightDX, rightDY, rightPeak, rightRise, rightFall, rightStrength)):
            return leftJoints.sorted() == rightJoints.sorted() && leftDX == rightDX && leftDY == rightDY
                && leftPeak == rightPeak && leftRise == rightRise && leftFall == rightFall && leftStrength == rightStrength
        case let (.depthScale(leftScale, leftReps), .depthScale(rightScale, rightReps)):
            return leftScale == rightScale && leftReps == rightReps
        case let (.asymmetry(leftSide, leftAmount), .asymmetry(rightSide, rightAmount)):
            return leftSide == rightSide && leftAmount == rightAmount
        case let (.tempo(leftScale, leftReps), .tempo(rightScale, rightReps)):
            return leftScale == rightScale && leftReps == rightReps
        case let (.pause(leftAt, leftDuration), .pause(rightAt, rightDuration)),
             let (.frameGap(leftAt, leftDuration), .frameGap(rightAt, rightDuration)):
            return leftAt == rightAt && leftDuration == rightDuration && lhs.kind == rhs.kind
        case let (.dropout(leftJoints, leftFrom, leftTo), .dropout(rightJoints, rightFrom, rightTo)):
            return leftJoints.sorted() == rightJoints.sorted() && leftFrom == rightFrom && leftTo == rightTo
        case let (.confidence(leftJoints, leftFrom, leftTo, leftValue),
                  .confidence(rightJoints, rightFrom, rightTo, rightValue)):
            return leftJoints.sorted() == rightJoints.sorted() && leftFrom == rightFrom && leftTo == rightTo
                && leftValue == rightValue
        case let (.framing(leftScale, leftX, leftY), .framing(rightScale, rightX, rightY)):
            return leftScale == rightScale && leftX == rightX && leftY == rightY
        default:
            return false
        }
    }

    func validate(path: String, reps: Int, sequenceDuration: TimeInterval?,
                  pauseClockDuration: TimeInterval?) -> [MovementValidationIssue] {
        var issues: [MovementValidationIssue] = []
        func finite(_ value: Double, _ field: String) {
            if !value.isFinite { issues.append(.init("\(path).\(field)", "must be finite")) }
        }
        func range(_ value: Double, _ bounds: ClosedRange<Double>, _ field: String) {
            finite(value, field)
            if value.isFinite && !bounds.contains(value) {
                issues.append(.init("\(path).\(field)", "must be between \(bounds.lowerBound) and \(bounds.upperBound)"))
            }
        }
        func time(_ value: TimeInterval, _ field: String, limit: TimeInterval? = nil) {
            finite(value, field)
            if value.isFinite, let limit = limit ?? sequenceDuration, (value < 0 || value > limit) {
                issues.append(.init("\(path).\(field)", "must be inside the sequence clock (0–\(limit) seconds)"))
            }
        }
        func joints(_ values: [String]) {
            if values.isEmpty { issues.append(.init("\(path).joints", "must contain at least one joint")) }
            let known = Set(LandmarkType.allCases.map(\.rawValue))
            for value in values where !known.contains(value) {
                issues.append(.init("\(path).joints", "unknown LandmarkType name '\(value)'"))
            }
            if Set(values).count != values.count {
                issues.append(.init("\(path).joints", "must not contain duplicate joint names"))
            }
        }
        func repSelection(_ selected: [Int]?, field: String) {
            guard let selected else { return }
            if selected.isEmpty { issues.append(.init("\(path).\(field)", "must not be empty when supplied")) }
            for rep in selected where rep < 1 || rep > reps {
                issues.append(.init("\(path).\(field)", "rep indices must be within 1...\(reps)"))
            }
            if Set(selected).count != selected.count {
                issues.append(.init("\(path).\(field)", "must not contain duplicates"))
            }
        }
        func duration(_ value: TimeInterval, _ field: String) {
            range(value, 0...10, field)
        }
        func interval(_ start: TimeInterval, _ end: TimeInterval, _ startField: String, _ endField: String) {
            time(start, startField)
            time(end, endField)
            if start.isFinite && end.isFinite && start > end {
                issues.append(.init("\(path).\(endField)", "must be at or after \(startField)"))
            } else if start.isFinite && end.isFinite && end - start > 10 {
                issues.append(.init("\(path).\(endField)", "interval duration must not exceed 10 seconds"))
            }
        }

        switch self {
        case .jointOffset(let affected, let dx, let dy, let peak, let rise, let fall, let strength):
            joints(affected)
            range(dx, -0.5...0.5, "dx")
            range(dy, -0.5...0.5, "dy")
            time(peak, "peak")
            duration(rise, "rise")
            duration(fall, "fall")
            range(strength, 0...1, "strength")
            if rise.isFinite && rise >= 0, peak - rise < 0 {
                issues.append(.init("\(path).rise", "influence start must be inside the output sequence"))
            }
            if fall.isFinite && fall >= 0, let sequenceDuration, peak + fall > sequenceDuration {
                issues.append(.init("\(path).fall", "influence end must be inside the output sequence"))
            }
        case .depthScale(let scale, let selected):
            range(scale, 0.3...2.0, "scale")
            repSelection(selected, field: "reps")
        case .asymmetry(_, let amount):
            range(amount, -0.5...0.5, "amount")
        case .tempo(let scale, let selected):
            range(scale, 0.3...2.0, "scale")
            repSelection(selected, field: "reps")
        case .pause(let at, let seconds):
            time(at, "at", limit: pauseClockDuration)
            duration(seconds, "duration")
        case .frameGap(let at, let seconds):
            time(at, "at")
            duration(seconds, "duration")
            if at.isFinite && seconds.isFinite, let sequenceDuration, at + seconds > sequenceDuration {
                issues.append(.init("\(path).duration", "frame-gap end must be at or before the output sequence end"))
            }
        case .dropout(let affected, let start, let end):
            joints(affected)
            interval(start, end, "from", "to")
        case .confidence(let affected, let start, let end, let value):
            joints(affected)
            interval(start, end, "from", "to")
            range(value, 0...1, "value")
        case .framing(let scale, let offsetX, let offsetY):
            range(scale, 0.3...2.0, "scale")
            range(offsetX, -0.5...0.5, "offsetX")
            range(offsetY, -0.5...0.5, "offsetY")
        }
        return issues
    }

    private enum CodingKeys: String, CodingKey {
        case kind, joints, dx, dy, peak, rise, fall, strength, scale, reps, side, amount
        case at, duration, from, to, value, offsetX, offsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "jointOffset":
            self = .jointOffset(joints: try container.decode([String].self, forKey: .joints).sorted(),
                                dx: try container.decode(Double.self, forKey: .dx),
                                dy: try container.decode(Double.self, forKey: .dy),
                                peak: try container.decode(TimeInterval.self, forKey: .peak),
                                rise: try container.decode(TimeInterval.self, forKey: .rise),
                                fall: try container.decode(TimeInterval.self, forKey: .fall),
                                strength: try container.decode(Double.self, forKey: .strength))
        case "depthScale":
            self = .depthScale(scale: try container.decode(Double.self, forKey: .scale),
                               reps: try container.decodeIfPresent([Int].self, forKey: .reps))
        case "asymmetry":
            let sideName = try container.decode(String.self, forKey: .side)
            guard let side = BodySide(rawValue: sideName) else {
                throw DecodingError.dataCorruptedError(forKey: .side, in: container,
                                                       debugDescription: "Unknown body side '\(sideName)'.")
            }
            self = .asymmetry(side: side, amount: try container.decode(Double.self, forKey: .amount))
        case "tempo":
            self = .tempo(scale: try container.decode(Double.self, forKey: .scale),
                          reps: try container.decodeIfPresent([Int].self, forKey: .reps))
        case "pause":
            self = .pause(at: try container.decode(TimeInterval.self, forKey: .at),
                          duration: try container.decode(TimeInterval.self, forKey: .duration))
        case "frameGap":
            self = .frameGap(at: try container.decode(TimeInterval.self, forKey: .at),
                             duration: try container.decode(TimeInterval.self, forKey: .duration))
        case "dropout":
            self = .dropout(joints: try container.decode([String].self, forKey: .joints).sorted(),
                            from: try container.decode(TimeInterval.self, forKey: .from),
                            to: try container.decode(TimeInterval.self, forKey: .to))
        case "confidence":
            self = .confidence(joints: try container.decode([String].self, forKey: .joints).sorted(),
                               from: try container.decode(TimeInterval.self, forKey: .from),
                               to: try container.decode(TimeInterval.self, forKey: .to),
                               value: try container.decode(Double.self, forKey: .value))
        case "framing":
            self = .framing(scale: try container.decode(Double.self, forKey: .scale),
                            offsetX: try container.decode(Double.self, forKey: .offsetX),
                            offsetY: try container.decode(Double.self, forKey: .offsetY))
        default:
            throw MovementScenarioSchemaError.unknownMutationKind(kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .jointOffset(let joints, let dx, let dy, let peak, let rise, let fall, let strength):
            try container.encode(joints.sorted(), forKey: .joints)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
            try container.encode(peak, forKey: .peak)
            try container.encode(rise, forKey: .rise)
            try container.encode(fall, forKey: .fall)
            try container.encode(strength, forKey: .strength)
        case .depthScale(let scale, let reps):
            try container.encode(scale, forKey: .scale)
            try container.encodeIfPresent(reps, forKey: .reps)
        case .tempo(let scale, let reps):
            try container.encode(scale, forKey: .scale)
            try container.encodeIfPresent(reps, forKey: .reps)
        case .asymmetry(let side, let amount):
            try container.encode(side.rawValue, forKey: .side)
            try container.encode(amount, forKey: .amount)
        case .pause(let at, let duration):
            try container.encode(at, forKey: .at)
            try container.encode(duration, forKey: .duration)
        case .frameGap(let at, let duration):
            try container.encode(at, forKey: .at)
            try container.encode(duration, forKey: .duration)
        case .dropout(let joints, let from, let to):
            try container.encode(joints.sorted(), forKey: .joints)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .confidence(let joints, let from, let to, let value):
            try container.encode(joints.sorted(), forKey: .joints)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(value, forKey: .value)
        case .framing(let scale, let offsetX, let offsetY):
            try container.encode(scale, forKey: .scale)
            try container.encode(offsetX, forKey: .offsetX)
            try container.encode(offsetY, forKey: .offsetY)
        }
    }
}

/// An assertion fixed in the plan before any scenario run.
enum MovementAssertion: Codable, Equatable {
    case repCount(equals: Int?, min: Int?, max: Int?)
    case rejection(reasonContains: String, countMin: Int)
    case formSignal(id: String, present: Bool)
    case framing(state: String, reached: Bool)
    case spokenCue(textContains: String, present: Bool)

    var kind: String {
        switch self {
        case .repCount: return "repCount"
        case .rejection: return "rejection"
        case .formSignal: return "formSignal"
        case .framing: return "framing"
        case .spokenCue: return "spokenCue"
        }
    }

    func validate(path: String) -> [MovementValidationIssue] {
        var issues: [MovementValidationIssue] = []
        switch self {
        case .repCount(let equals, let min, let max):
            if let equals, equals < 0 { issues.append(.init("\(path).equals", "must be non-negative")) }
            if let min, min < 0 { issues.append(.init("\(path).min", "must be non-negative")) }
            if let max, max < 0 { issues.append(.init("\(path).max", "must be non-negative")) }
            if equals == nil && min == nil && max == nil {
                issues.append(.init(path, "repCount needs equals or at least one of min/max"))
            }
            if equals != nil && (min != nil || max != nil) {
                issues.append(.init(path, "repCount must use equals or a min/max range, not both"))
            }
            if let min, let max, min > max {
                issues.append(.init(path, "min must not exceed max"))
            }
        case .rejection(let reasonContains, let countMin):
            if reasonContains.isEmpty { issues.append(.init("\(path).reasonContains", "must not be empty")) }
            if countMin < 0 { issues.append(.init("\(path).countMin", "must be non-negative")) }
        case .formSignal(let id, _):
            if id.isEmpty { issues.append(.init("\(path).id", "must not be empty")) }
        case .framing(let state, _):
            if state.isEmpty { issues.append(.init("\(path).state", "must not be empty")) }
        case .spokenCue(let textContains, _):
            if textContains.isEmpty { issues.append(.init("\(path).textContains", "must not be empty")) }
        }
        return issues
    }

    private enum CodingKeys: String, CodingKey {
        case kind, equals, min, max, reasonContains, countMin, id, present, state, reached, textContains
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "repCount":
            self = .repCount(equals: try container.decodeIfPresent(Int.self, forKey: .equals),
                             min: try container.decodeIfPresent(Int.self, forKey: .min),
                             max: try container.decodeIfPresent(Int.self, forKey: .max))
        case "rejection":
            self = .rejection(reasonContains: try container.decode(String.self, forKey: .reasonContains),
                              countMin: try container.decode(Int.self, forKey: .countMin))
        case "formSignal":
            self = .formSignal(id: try container.decode(String.self, forKey: .id),
                               present: try container.decode(Bool.self, forKey: .present))
        case "framing":
            self = .framing(state: try container.decode(String.self, forKey: .state),
                            reached: try container.decode(Bool.self, forKey: .reached))
        case "spokenCue":
            self = .spokenCue(textContains: try container.decode(String.self, forKey: .textContains),
                              present: try container.decode(Bool.self, forKey: .present))
        default:
            throw MovementScenarioSchemaError.unknownAssertionKind(kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .repCount(let equals, let min, let max):
            try container.encodeIfPresent(equals, forKey: .equals)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)
        case .rejection(let reasonContains, let countMin):
            try container.encode(reasonContains, forKey: .reasonContains)
            try container.encode(countMin, forKey: .countMin)
        case .formSignal(let id, let present):
            try container.encode(id, forKey: .id)
            try container.encode(present, forKey: .present)
        case .framing(let state, let reached):
            try container.encode(state, forKey: .state)
            try container.encode(reached, forKey: .reached)
        case .spokenCue(let textContains, let present):
            try container.encode(textContains, forKey: .textContains)
            try container.encode(present, forKey: .present)
        }
    }
}

/// Result labels reserved for the batch runner in the next milestone.
enum MovementOutcome: String, Codable, CaseIterable {
    case passed
    case failed
    case inconclusive
    case invalid
    case notRun
}

/// What a future batch runner observed while checking a scenario.
struct MovementObserved: Codable, Equatable {
    var reps: Int?
    var rejections: [String]
    var signals: [String]
    var framingChanges: [String]
    var cues: [String]

    init(reps: Int? = nil, rejections: [String] = [], signals: [String] = [],
         framingChanges: [String] = [], cues: [String] = []) {
        self.reps = reps
        self.rejections = rejections
        self.signals = signals
        self.framingChanges = framingChanges
        self.cues = cues
    }
}

/// One assertion evaluation produced by a future batch runner.
struct MovementAssertionResult: Codable, Equatable {
    var assertionIndex: Int
    var passed: Bool
    var detail: String
}

/// Stored status and observations for one scenario revision.
struct MovementScenarioResult: Codable, Equatable {
    var scenarioID: String
    var revision: Int
    var outcome: MovementOutcome
    var observed: MovementObserved
    var assertionResults: [MovementAssertionResult]
    var invalidReasons: [String]
}

enum MovementISO8601 {
    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: text)
    }
}

enum MovementValidation {
    static func isValidID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45 || byte == 95
        }
    }
}
