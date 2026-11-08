import CoreGraphics
import Foundation
@testable import PostureAnalysisApp

enum ReplayError: Error, CustomStringConvertible {
    case noHeader
    case malformed(line: Int)
    case missing(String, line: Int)
    case unknownJoint(String)
    case unknownExercise(String, line: Int)
    case unsupportedCameraView(String, exercise: String, line: Int)
    case unknownControl(String, line: Int)
    case unknownPhase(String, line: Int)
    case frameWithoutExercise(line: Int)
    case invalid(String, line: Int)
    case definitionDrift(String, exercise: String)

    var description: String {
        switch self {
        case .noHeader: return "no header record"
        case .malformed(let line): return "line \(line) isn't a JSON record"
        case .missing(let field, let line): return "line \(line) lacks \(field)"
        case .unknownJoint(let name): return "unknown joint \(name) in jointOrder"
        case .unknownExercise(let id, let line): return "line \(line): exercise \(id) isn't in this build's catalog"
        case .unsupportedCameraView(let view, let id, let line):
            return "line \(line): \(id) was filmed \(view), which this build's \(id) doesn't use"
        case .unknownControl(let control, let line): return "line \(line): unknown control \(control)"
        case .unknownPhase(let phase, let line): return "line \(line): unknown phase \(phase)"
        case .frameWithoutExercise(let line): return "line \(line): an analyzed frame before any exercise control"
        case .invalid(let field, let line): return "line \(line): invalid \(field)"
        case .definitionDrift(let field, let id):
            return "\(id)'s \(field) changed since this recording, so replay can't reproduce its framing"
        }
    }
}

/// A workout recording read back for replay: its header and records in file order, with their line numbers. Only a
/// cut-off final record (a crash mid-write) is tolerated; a bad record anywhere else is an error.
struct WorkoutSessionFile {
    let header: [String: Any]
    let records: [(line: Int, record: [String: Any])]

    init(text: String) throws {
        let lines = text.components(separatedBy: .newlines).enumerated()
            .map { (number: $0.offset + 1, text: $0.element.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.text.isEmpty }
        let isClosed = lines.last?.text == "]"
        var records: [(line: Int, record: [String: Any])] = []
        for (index, line) in lines.enumerated() {
            if line.text == "[" || line.text == "]" { continue }
            var body = line.text
            if body.hasSuffix(",") { body.removeLast() }
            guard body.hasPrefix("{"), let record = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] else {
                // Only the unfinished tail of a recording that never closed can be a write the crash cut off.
                if index == lines.count - 1, !isClosed { break }
                throw ReplayError.malformed(line: line.number)
            }
            records.append((line.number, record))
        }
        guard let header = records.first(where: { $0.record["k"] as? String == "header" })?.record else {
            throw ReplayError.noHeader
        }
        self.header = header
        self.records = records
    }

    init(url: URL) throws {
        try self.init(text: String(contentsOf: url, encoding: .utf8))
    }
}

/// Runs a recording's analyzed frames and pipeline controls through a fresh `WorkoutFramePipeline`, in the order the
/// phone ran them, with the recorded framing, off-edge, and exercise configurations.
struct WorkoutSessionReplayer {
    /// What counting depends on for one analyzed frame: rep events, framing reliability, the counting flag, and
    /// whether the start position is held. Guidance wording isn't compared, so new guidance doesn't fail old recordings.
    struct Outcome: Equatable, CustomStringConvertible {
        var reps: [String]
        var reliable: Bool?
        var counting: Bool?
        var startHeld: Bool

        var description: String {
            "reps \(reps) reliable \(reliable.map(String.init) ?? "-") counting \(counting.map(String.init) ?? "-") start \(startHeld)"
        }
    }

    struct Frame {
        let line: Int
        let t: TimeInterval
        let recorded: Outcome
        let replayed: Outcome
        let rejections: [RepRejection]
    }

    static func replay(_ file: WorkoutSessionFile, catalog: [ExerciseDefinition] = ExerciseCatalog.all) throws -> [Frame] {
        let header = file.header
        let exercises = try definitions(header, catalog: catalog)
        guard let jointNames = header["jointOrder"] as? [String] else { throw ReplayError.missing("jointOrder", line: 1) }
        let joints = try jointNames.map { name in
            guard let joint = LandmarkType(rawValue: name) else { throw ReplayError.unknownJoint(name) }
            return joint
        }
        var pipeline = WorkoutFramePipeline(framingConfiguration: try recorded(header["framing"], over: FramingConfiguration()),
                                            offscreenConfiguration: try recorded(header["offscreen"], over: OffscreenJointConfiguration()))
        pipeline.collectsDiagnostics = true
        var imageSize: CGSize?
        var frames: [Frame] = []
        for (line, record) in file.records {
            switch record["k"] as? String {
            case "pipe":
                _ = pipeline.apply(try control(record, line: line, exercises: exercises))
            case "f":
                if let value = record["wh"] {
                    guard let size = value as? [Double], size.count == 2, size[0] > 0, size[1] > 0 else {
                        throw ReplayError.invalid("wh", line: line)
                    }
                    imageSize = CGSize(width: size[0], height: size[1])
                }
                guard let processed = record["p"] as? Bool else { throw ReplayError.invalid("p", line: line) }
                // Frames nothing analyzed on the phone (no exercise, or from before a command) aren't analyzed here.
                guard processed else { continue }
                guard pipeline.exercise != nil else { throw ReplayError.frameWithoutExercise(line: line) }
                guard let ts = record["ts"] as? Double else { throw ReplayError.missing("ts", line: line) }
                guard let size = imageSize else { throw ReplayError.missing("wh before the first frame", line: line) }
                guard let values = record["j"] as? [Any] else { throw ReplayError.missing("j", line: line) }
                let t = record["t"] as? Double ?? 0
                let output = pipeline.process(frame: PoseFrame(pose: pose(values, joints: joints, size: size), timestamp: ts), at: t)
                frames.append(Frame(line: line, t: t, recorded: recordedOutcome(record), replayed: replayedOutcome(output),
                                    rejections: output.diagnostics?.analysis?.rejections ?? []))
            default:
                continue
            }
        }
        return frames
    }

    /// Catalog exercises rebuilt from the configurations the recording carries. What framing and off-edge estimation
    /// read from the definition itself must match the recording, or replay can't reproduce its framing.
    static func definitions(_ header: [String: Any], catalog: [ExerciseDefinition]) throws -> [String: ExerciseDefinition] {
        let recorded = header["exercises"] as? [String: Any] ?? [:]
        var definitions: [String: ExerciseDefinition] = [:]
        for exercise in catalog {
            let id = exercise.id.rawValue
            guard let entry = recorded[id] as? [String: Any] else {
                definitions[id] = exercise
                continue
            }
            try checkDrift(entry, exercise)
            guard let configuration = entry["configuration"] as? [String: Any], let diagnostics = exercise.diagnostics else {
                definitions[id] = exercise
                continue
            }
            definitions[id] = try diagnostics.rebuild(JSONSerialization.data(withJSONObject: configuration))
        }
        // A smaller-range variant keeps its own recorded configuration. A recording without one (every recording from
        // before variants were recorded) runs this build's variant, and a control that names none runs the full range.
        for exercise in catalog {
            guard let variant = exercise.reducedRange?() else { continue }
            let key = "\(exercise.id.rawValue).\(WorkoutSessionLines.reducedRangeVariant)"
            guard let entry = recorded[key] as? [String: Any], let configuration = entry["configuration"] as? [String: Any],
                  let diagnostics = variant.diagnostics else {
                definitions[key] = variant
                continue
            }
            definitions[key] = try diagnostics.rebuild(JSONSerialization.data(withJSONObject: configuration))
        }
        return definitions
    }

    private static func checkDrift(_ entry: [String: Any], _ exercise: ExerciseDefinition) throws {
        func names(_ joints: Set<LandmarkType>) -> [String] { joints.map(\.rawValue).sorted() }
        func check(_ field: String, _ current: Any) throws {
            guard let value = entry[field] else { return }
            if let joints = current as? [String], (value as? [String])?.sorted() == joints { return }
            if let sets = current as? [[String]], (value as? [[String]])?.map({ $0.sorted() }).sorted(by: { $0.lexicographicallyPrecedes($1) })
                == sets.sorted(by: { $0.lexicographicallyPrecedes($1) }) { return }
            if let number = current as? Double?, (value as? Double) == number || (value is NSNull && number == nil) { return }
            throw ReplayError.definitionDrift(field, exercise: exercise.id.rawValue)
        }
        try check("required", names(exercise.requiredJoints))
        try check("anyOfRequired", exercise.anyOfRequiredJoints.map(names))
        try check("focus", names(exercise.focusJoints))
        try check("planted", names(exercise.plantedJoints))
        try check("sideroomArmLengths", exercise.sideroomArmLengths.map(Double.init) as Double?)
    }

    static func control(_ record: [String: Any], line: Int,
                        exercises: [String: ExerciseDefinition]) throws -> WorkoutFramePipeline.Control {
        let name = record["control"] as? String ?? "(none)"
        switch name {
        case "sessionPhase":
            let label = record["phase"] as? String ?? ""
            guard let phase = phase(label) else { throw ReplayError.unknownPhase(label, line: line) }
            return .sessionPhase(phase)
        case "exercise":
            guard let epoch = record["epoch"] as? Int else { throw ReplayError.missing("epoch", line: line) }
            guard let id = record["exercise"] as? String else { return .exercise(nil, analyzerEpoch: epoch) }
            let key = (record["variant"] as? String).map { "\(id).\($0)" } ?? id
            guard let exercise = exercises[key] else { throw ReplayError.unknownExercise(key, line: line) }
            if let view = record["cameraView"] as? String, view != exercise.cameraView.rawValue {
                throw ReplayError.unsupportedCameraView(view, exercise: id, line: line)
            }
            return .exercise(exercise, analyzerEpoch: epoch)
        case "resetAnalyzer":
            guard let epoch = record["epoch"] as? Int else { throw ReplayError.missing("epoch", line: line) }
            return .resetAnalyzer(epoch: epoch)
        case "counting":
            guard let counting = record["counting"] as? Bool else { throw ReplayError.missing("counting", line: line) }
            return .counting(counting)
        case "resetTracking":
            return .resetTracking
        default:
            throw ReplayError.unknownControl(name, line: line)
        }
    }

    /// The phase from `WorkoutStateSnapshot.label`.
    static func phase(_ label: String) -> WorkoutPhase? {
        switch label {
        case "choosingExercise": return .choosingExercise
        case "framing": return .framing
        case "ready": return .ready
        case "exercising": return .exercising
        case "resting": return .resting
        case "exerciseComplete": return .exerciseComplete
        case "ended": return .ended
        case "paused(user)": return .paused(.user)
        case "paused(background)": return .paused(.background)
        case "paused(interruption)": return .paused(.interruption)
        default:
            guard label.hasPrefix("changingExercise("), label.hasSuffix(")"),
                  let previous = phase(String(label.dropFirst("changingExercise(".count).dropLast())) else { return nil }
            return .changingExercise(previous: previous)
        }
    }

    /// A recorded configuration laid over this build's, as `ExerciseDiagnostics.rebuild` does for exercises.
    private static func recorded<Configuration: Codable>(_ value: Any?, over current: Configuration) throws -> Configuration {
        guard let object = value as? [String: Any] else { return current }
        let merged = try ExerciseDiagnostics.merge(JSONSerialization.data(withJSONObject: object),
                                                   over: ExerciseDiagnostics.encoder.encode(current))
        return try JSONDecoder().decode(Configuration.self, from: merged)
    }

    private static func recordedOutcome(_ record: [String: Any]) -> Outcome {
        let reps = (record["out"] as? [[String: Any]] ?? []).compactMap { event -> String? in
            guard let rep = event["rep"] as? [String: Any] else { return nil }
            return describe(ts: rep["ts"] as? Double, epoch: rep["epoch"] as? Int, sides: rep["sides"] as? [String] ?? [])
        }
        return Outcome(reps: reps, reliable: (record["fr"] as? [String: Any])?["ok"] as? Bool,
                       counting: record["cnt"] as? Bool, startHeld: record["start"] as? Bool ?? false)
    }

    private static func replayedOutcome(_ output: WorkoutFramePipeline.FrameOutput) -> Outcome {
        let reps = output.events.compactMap { event -> String? in
            guard case .repCompleted(let rep) = event else { return nil }
            return describe(ts: rep.timestamp, epoch: rep.epoch, sides: rep.sides.map(\.rawValue))
        }
        return Outcome(reps: reps, reliable: output.diagnostics?.framing?.isReliable,
                       counting: output.diagnostics?.counting, startHeld: output.diagnostics?.analysis?.startPositionHeld ?? false)
    }

    private static func describe(ts: Double?, epoch: Int?, sides: [String]) -> String {
        "\(ts.map { String($0) } ?? "?")#\(epoch.map(String.init) ?? "?")[\(sides.sorted().joined(separator: "+"))]"
    }

    private static func pose(_ values: [Any], joints: [LandmarkType], size: CGSize) -> BodyPose {
        var landmarks: [LandmarkType: Landmark] = [:]
        for (index, value) in values.enumerated() where index < joints.count {
            guard let point = value as? [Double], point.count == 3 else { continue }
            let pixel = CGPoint(x: point[0], y: point[1])
            landmarks[joints[index]] = Landmark(type: joints[index],
                                                normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                                    pixel: pixel, imageWidth: size.width, imageHeight: size.height),
                                                imageLocation: pixel, confidence: point[2])
        }
        return BodyPose(landmarks: landmarks, imageWidth: size.width, imageHeight: size.height)
    }
}
