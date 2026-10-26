import CoreGraphics
import Foundation

/// Builds the lines of a `.json` recording (schema `fmp.workout-session/1`; see `docs/diagnostics.md`).
/// Each record is one JSON object, on a line of its own, whose `k` names its kind. `t` is seconds since the recording began.
enum WorkoutSessionLines {
    static let schema = "fmp.workout-session/1"
    /// Frame joints are written in this order, by index.
    static let jointOrder = LandmarkType.allCases
    private static let jointIndex = Dictionary(uniqueKeysWithValues: jointOrder.enumerated().map { ($1, $0) })

    struct AppInfo {
        var version: String
        var build: String
        var configuration: String
        var deviceModel: String
        var systemVersion: String

        static var current: AppInfo {
            let info = Bundle.main.infoDictionary ?? [:]
            #if DEBUG
            let configuration = "Debug"
            #else
            let configuration = "Release"
            #endif
            var system = utsname()
            uname(&system)
            let model = withUnsafeBytes(of: &system.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return AppInfo(version: info["CFBundleShortVersionString"] as? String ?? "?",
                           build: info["CFBundleVersion"] as? String ?? "?",
                           configuration: configuration,
                           deviceModel: model,
                           systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        }
    }

    // MARK: - Header

    static func header(id: UUID, context: WorkoutRecordingContext, app: AppInfo) -> DiagnosticJSON {
        return .object(
            ("k", "header"),
            ("schema", .string(schema)),
            ("kind", "workout"),
            ("id", .string(id.uuidString)),
            ("startedAt", .string(timestamp(context.startedAt, timeZone: context.timeZone))),
            ("timeZone", .string(context.timeZone.identifier)),
            ("app", .object(("version", .string(app.version)), ("build", .string(app.build)),
                            ("configuration", .string(app.configuration)))),
            ("device", .object(("model", .string(app.deviceModel)), ("os", .string(app.systemVersion)))),
            ("camera", .object(("position", "front"),
                               ("analysisHz", .int(WorkoutCameraController.frameRate)),
                               ("space", "image pixels, origin top-left, unmirrored"),
                               ("previewMirrored", true))),
            ("jointOrder", .array(jointOrder.map { .string($0.rawValue) })),
            ("confidenceFloor", .double(RealtimePoseProcessing.liveConfidenceFloor)),
            ("settings", settings(context)),
            ("plan", context.plan.map(plan)),
            ("exercises", .object(context.exercises.map { (key: $0.id.rawValue, value: exercise($0)) })),
            ("framing", .raw(ExerciseDiagnostics.json(FramingConfiguration()))),
            ("offscreen", .raw(ExerciseDiagnostics.json(OffscreenJointConfiguration()))),
            ("cueScheduler", .raw(ExerciseDiagnostics.json(CoachingCueScheduler.Configuration()))),
            ("constants", constants)
        )
    }

    private static func settings(_ context: WorkoutRecordingContext) -> DiagnosticJSON {
        let rest: DiagnosticJSON
        switch context.settings.restPolicy {
        case .exerciseDefault: rest = "exerciseDefault"
        case .fixed(let seconds): rest = .object(("fixedSeconds", .int(seconds)))
        }
        return .object(
            ("restPolicy", rest),
            ("weightUnit", .string(context.settings.weightUnit.rawValue)),
            ("startByHolding", .bool(context.settings.startByHolding)),
            ("tiltWarnings", .bool(context.tiltWarningsEnabled)),
            ("coachMuted", .bool(context.isCoachMuted)),
            ("micMuted", .bool(context.isMicMuted))
        )
    }

    private static func plan(_ plan: WorkoutPlan) -> DiagnosticJSON {
        .object(
            ("id", plan.id.map { .string($0.uuidString) }),
            ("name", .string(plan.name)),
            ("items", .array(plan.items.map { item in
                .object(("id", .string(item.id.uuidString)), ("exercise", .string(item.exerciseID.rawValue)),
                        ("sets", .int(item.sets)),
                        ("reps", [.int(item.targetReps.lowerBound), .int(item.targetReps.upperBound)]))
            }))
        )
    }

    private static func exercise(_ exercise: ExerciseDefinition) -> DiagnosticJSON {
        func joints(_ joints: Set<LandmarkType>) -> DiagnosticJSON { .strings(joints.map(\.rawValue)) }
        func cue(_ cue: CoachingCue) -> DiagnosticJSON {
            .object(("id", .string(cue.id.rawValue)), ("text", .string(cue.text)),
                    ("kind", cue.kind == .corrective ? "corrective" : "reminder"),
                    ("trigger", cue.trigger == .perRep ? "perRep" : "continuous"),
                    ("priority", .int(cue.priority)))
        }
        return .object(
            ("name", .string(exercise.displayName)),
            ("cameraView", .string(exercise.cameraView.rawValue)),
            ("sets", .int(exercise.sets)),
            ("reps", [.int(exercise.targetReps.lowerBound), .int(exercise.targetReps.upperBound)]),
            ("autoCompleteReps", .int(exercise.autoCompleteReps)),
            ("required", joints(exercise.requiredJoints)),
            ("anyOfRequired", .array(exercise.anyOfRequiredJoints.map(joints))),
            ("focus", joints(exercise.focusJoints)),
            ("planted", joints(exercise.plantedJoints)),
            ("headroomArmLengths", .number(exercise.headroomArmLengths)),
            ("sideroomArmLengths", .number(exercise.sideroomArmLengths)),
            ("perSide", .bool(exercise.perSide)),
            ("countsArmsIndependently", .bool(exercise.countsArmsIndependently)),
            ("startsByHolding", .bool(exercise.startsByHolding)),
            ("warnsAboutTilt", .bool(exercise.warnsAboutTilt)),
            ("configuration", exercise.diagnostics.map { .raw($0.configurationJSON) }),
            ("cues", .array((exercise.coachingCues + exercise.reminders).map(cue)))
        )
    }

    /// Fixed tunables that live in `static let`s rather than a configuration.
    private static var constants: DiagnosticJSON {
        .object(
            ("tiltedPitch", .double(PhoneTiltPolicy.tiltedPitch)),
            ("uprightPitch", .double(PhoneTiltPolicy.uprightPitch)),
            ("tiltSettleTime", .double(PhoneTiltPolicy.settleTime)),
            ("tickInterval", .double(WorkoutCoachModel.tickInterval)),
            ("guidanceSettleTime", .double(WorkoutSession.guidanceSettleTime)),
            ("guidanceRepeatInterval", .double(WorkoutSession.guidanceRepeatInterval)),
            ("trackingLossGrace", .double(WorkoutSession.trackingLossGrace)),
            ("startHoldDuration", .double(WorkoutSession.startHoldDuration)),
            ("tiltWarningInterval", .double(WorkoutSession.tiltWarningInterval))
        )
    }

    // MARK: - Lines

    static func control(_ control: WorkoutFramePipeline.Control, t: TimeInterval) -> DiagnosticJSON {
        let fields: [(key: String, value: DiagnosticJSON)]
        switch control {
        case .sessionPhase(let phase):
            fields = [("control", "sessionPhase"), ("phase", .string(WorkoutStateSnapshot.label(phase)))]
        case .exercise(let exercise, let epoch):
            fields = [("control", "exercise"),
                      ("exercise", exercise.map { .string($0.id.rawValue) } ?? .null),
                      ("cameraView", exercise.map { .string($0.cameraView.rawValue) } ?? .null),
                      ("epoch", .int(epoch))]
        case .resetAnalyzer(let epoch):
            fields = [("control", "resetAnalyzer"), ("epoch", .int(epoch))]
        case .counting(let counting):
            fields = [("control", "counting"), ("counting", .bool(counting))]
        case .resetTracking:
            fields = [("control", "resetTracking")]
        }
        return .object([("k", "pipe"), ("t", time(t))] + fields)
    }

    /// One analyzed (or, with no exercise, unprocessed) camera frame. Joints are the pose as the pipeline
    /// received it, exactly; `est` lists joints the pipeline estimated past the frame edge for this frame.
    static func frame(_ frame: PoseFrame, output: WorkoutFramePipeline.FrameOutput?, pitchDegrees: Double?,
                      imageSizeChanged: Bool, t: TimeInterval) -> DiagnosticJSON {
        let diagnostics = output?.diagnostics
        var members: [(key: String, value: DiagnosticJSON)] = [
            ("k", "f"), ("t", time(t)), ("ts", .double(frame.timestamp))
        ]
        if let sequence = frame.sequence { members.append(("seq", .int(sequence))) }
        if frame.deliveryDelay > 0 { members.append(("delay", .rounded(frame.deliveryDelay, places: 3))) }
        members.append(("p", .bool(output != nil)))
        if let diagnostics { members.append(("cnt", .bool(diagnostics.counting))) }
        if imageSizeChanged {
            members.append(("wh", [.double(Double(frame.pose.imageWidth)), .double(Double(frame.pose.imageHeight))]))
        }
        members.append(("j", .array(jointOrder.map { joint in
            guard let landmark = frame.pose[joint] else { return .null }
            return [.double(Double(landmark.imageLocation.x)), .double(Double(landmark.imageLocation.y)),
                    .double(landmark.confidence)]
        })))
        if !frame.lowConfidenceLandmarks.isEmpty {
            members.append(("lo", .array(sortedByJoint(frame.lowConfidenceLandmarks).map { joint, landmark in
                [.int(jointIndex[joint] ?? -1), .rounded(Double(landmark.imageLocation.x), places: 1),
                 .rounded(Double(landmark.imageLocation.y), places: 1), .rounded(landmark.confidence, places: 3)]
            })))
        }
        if let analyzed = diagnostics?.analyzedFrame, !analyzed.estimatedJoints.isEmpty {
            members.append(("est", .array(analyzed.estimatedJoints.sorted { index($0) < index($1) }.compactMap { joint in
                analyzed.pose[joint].map {
                    [.int(index(joint)), .double(Double($0.imageLocation.x)), .double(Double($0.imageLocation.y))]
                }
            })))
        }
        if let pitchDegrees { members.append(("pitch", .rounded(pitchDegrees, places: 2))) }
        if let diagnostics, let framing = diagnostics.framing {
            members.append(("fr", self.framing(framing)))
        }
        if let output, !output.events.isEmpty {
            members.append(("out", .array(output.events.compactMap(pipelineEvent))))
        }
        if let analysis = diagnostics?.analysis {
            if !analysis.readings.isEmpty {
                members.append(("rd", .object(sortedBySide(analysis.readings).map { side, reading in
                    (key: side.rawValue, value: .object(("signal", .rounded(reading.signal)),
                                                         ("elbow", .rounded(reading.elbowAngle, places: 2)),
                                                         ("zone", .string(reading.zone.rawValue))))
                })))
            }
            if !analysis.thresholds.isEmpty {
                members.append(("th", .object(sortedBySide(analysis.thresholds).map { side, thresholds in
                    (key: side.rawValue, value: self.thresholds(thresholds))
                })))
            }
            if !analysis.formSignals.isEmpty {
                members.append(("sig", .strings(analysis.formSignals.map(\.rawValue))))
            }
            if !analysis.repForms.isEmpty {
                members.append(("forms", .array(analysis.repForms.map { form in
                    .object(("ts", .double(form.timestamp)), ("flags", .strings(form.flags.map(\.rawValue))))
                })))
            }
            if !analysis.formReadings.isEmpty {
                members.append(("fv", .object(analysis.formReadings.map { (key: $0.label, value: .string($0.value)) })))
            }
            if !analysis.endPositionSides.isEmpty {
                members.append(("end", .strings(analysis.endPositionSides.map(\.rawValue))))
            }
            if analysis.startPositionHeld { members.append(("start", true)) }
        }
        return .object(members)
    }

    static func state(_ snapshot: WorkoutStateSnapshot, restEndsT: TimeInterval?, t: TimeInterval) -> DiagnosticJSON {
        .object(
            ("k", "state"), ("t", time(t)),
            ("phase", .string(snapshot.phase)),
            ("ex", snapshot.exerciseID.map { .string($0) } ?? .null),
            ("planIndex", snapshot.planIndex.map { .int($0) }),
            ("set", .int(snapshot.setNumber)),
            ("side", snapshot.side.map { .string($0) }),
            ("reps", .int(snapshot.repCount)),
            ("sideReps", .object(("left", .int(snapshot.leftReps)), ("right", .int(snapshot.rightReps)))),
            ("counting", .bool(snapshot.isCounting)),
            ("epoch", .int(snapshot.analyzerEpoch)),
            ("framing", .object(("ok", .bool(snapshot.framingReliable)),
                                ("g", snapshot.framingGuidance.map { .string($0) } ?? .null))),
            ("restEnds", restEndsT.map(time)),
            ("tilted", .bool(snapshot.isPhoneTilted)),
            ("tip", snapshot.tipCueID.map { .string($0) } ?? .null),
            ("speaking", .bool(snapshot.isCoachSpeaking)),
            ("mic", .string(snapshot.micStatus)),
            ("coachMuted", .bool(snapshot.isCoachMuted)),
            ("micMuted", .bool(snapshot.isMicMuted)),
            ("camera", .string(snapshot.cameraStatus))
        )
    }

    static func event(_ event: WorkoutRecordingEvent, t: TimeInterval) -> DiagnosticJSON {
        let fields: [(key: String, value: DiagnosticJSON)]
        switch event {
        case .input(let input):
            fields = inputFields(input)
        case .command(let command, let source, let phrase):
            fields = [("type", "command"), ("command", .string(label(command))), ("source", .string(source.rawValue))]
                + (phrase.map { [("phrase", .string($0))] } ?? [])
        case .speak(let utterance, let muted):
            fields = [("type", "speak"), ("text", .string(utterance.text)),
                      ("instruction", .bool(utterance.isInstruction)), ("interrupts", .bool(utterance.interrupts)),
                      ("muted", .bool(muted))]
        case .repeatLastInstruction(let muted):
            fields = [("type", "repeatLast"), ("muted", .bool(muted))]
        case .tipShown(let tip):
            fields = [("type", "tip"), ("cue", .string(tip.cue.id.rawValue)),
                      ("kind", tip.cue.kind == .corrective ? "corrective" : "reminder"), ("text", .string(tip.cue.text))]
        case .tipCleared:
            fields = [("type", "tip.cleared")]
        case .clearFeedback:
            fields = [("type", "clearFeedback")]
        case .cameraRunning:
            fields = [("type", "camera.running")]
        case .cameraInterrupted:
            fields = [("type", "camera.interrupted")]
        case .cameraFailed(let message):
            fields = [("type", "camera.failed"), ("message", .string(message))]
        case .audioInterruptionBegan:
            fields = [("type", "audio.interruptionBegan")]
        case .audioInterruptionEnded(let shouldResume):
            fields = [("type", "audio.interruptionEnded"), ("shouldResume", .bool(shouldResume))]
        case .guidePresented(let shown):
            fields = [("type", "ui.guide"), ("shown", .bool(shown))]
        case .helpPresented(let shown):
            fields = [("type", "ui.help"), ("shown", .bool(shown))]
        case .measurementsShown(let shown):
            fields = [("type", "ui.measurements"), ("shown", .bool(shown))]
        }
        return .object([("k", "e"), ("t", time(t))] + fields)
    }

    /// `t` is when the marker was recorded; `heardAt` is when its trigger was heard, which a dictated note can
    /// precede by a second or two.
    static func marker(_ marker: WorkoutMarker, heardT: TimeInterval?, recordedT: TimeInterval,
                       context: DiagnosticJSON) -> DiagnosticJSON {
        .object(
            ("k", "marker"), ("t", time(recordedT)),
            ("heardAt", heardT.map(time)),
            ("id", .string(marker.id.uuidString)),
            ("source", .string(marker.source.rawValue)),
            ("text", marker.note.map { .string($0) }),
            ("ctx", context)
        )
    }

    static func end(_ reason: WorkoutRecordingEnd, endedAt: Date, timeZone: TimeZone, frames: Int, sequenceGaps: Int,
                    workoutRecordID: UUID?, t: TimeInterval) -> DiagnosticJSON {
        .object(
            ("k", "end"), ("t", time(t)),
            ("endedAt", .string(timestamp(endedAt, timeZone: timeZone))),
            ("reason", .string(reason.rawValue)),
            ("frames", .int(frames)),
            ("seqGaps", .int(sequenceGaps)),
            ("workoutRecordID", workoutRecordID.map { .string($0.uuidString) } ?? .null)
        )
    }

    // MARK: - Pieces

    /// ISO 8601 with milliseconds and the local offset, such as "2026-10-25T21:19:19.906-07:00".
    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Recording time to the millisecond; frames carry their exact capture time in `ts`.
    static func time(_ t: TimeInterval) -> DiagnosticJSON { .rounded(t, places: 3) }

    static func framing(_ status: FramingStatus) -> DiagnosticJSON {
        .object(("ok", .bool(status.isReliable)), ("g", status.guidance.map { .string($0.rawValue) } ?? .null))
    }

    private static func thresholds(_ thresholds: ArmThresholds) -> DiagnosticJSON {
        func line(_ line: ThresholdLine) -> DiagnosticJSON {
            [.rounded(Double(line.from.x), places: 1), .rounded(Double(line.from.y), places: 1),
             .rounded(Double(line.to.x), places: 1), .rounded(Double(line.to.y), places: 1)]
        }
        let confirmed: DiagnosticJSON = thresholds.confirmed.map { $0 == .start ? "start" : "top" } ?? .null
        return .object(("start", line(thresholds.startLine)), ("top", line(thresholds.topLine)),
                       ("locked", .bool(thresholds.isLocked)), ("confirmed", confirmed))
    }

    /// The pipeline's own output events for a frame, compared exactly by replay.
    private static func pipelineEvent(_ event: WorkoutEvent) -> DiagnosticJSON? {
        switch event {
        case .repCompleted(let rep):
            return .object(("rep", .object(("epoch", .int(rep.epoch)), ("ts", .double(rep.timestamp)),
                                           ("sides", .strings(rep.sides.map(\.rawValue))))))
        case .framingChanged(let status):
            return .object(("framing", framing(status)))
        case .startPositionChanged(let held):
            return .object(("start", .bool(held)))
        case .formObserved:
            // Form output already has its own frame fields.
            return nil
        default:
            return .object(("other", .string(String(describing: event))))
        }
    }

    private static func inputFields(_ event: WorkoutEvent) -> [(key: String, value: DiagnosticJSON)] {
        switch event {
        case .opened: return [("type", "opened")]
        case .framingChanged(let status): return [("type", "framing"), ("framing", framing(status))]
        case .repCompleted(let rep):
            return [("type", "rep"), ("epoch", .int(rep.epoch)), ("ts", .double(rep.timestamp)),
                    ("sides", .strings(rep.sides.map(\.rawValue)))]
        case .startPositionChanged(let held): return [("type", "startPosition"), ("held", .bool(held))]
        case .phoneTiltChanged(let tilted): return [("type", "tilt"), ("tilted", .bool(tilted))]
        case .appBackgrounded: return [("type", "app.background")]
        case .appForegrounded: return [("type", "app.foreground")]
        case .interruptionBegan: return [("type", "interruptionBegan")]
        case .interruptionEnded: return [("type", "interruptionEnded")]
        case .voiceControlChanged(let active): return [("type", "voiceControl"), ("active", .bool(active))]
        case .tick, .command, .formObserved, .coachSpeakingChanged, .poseObserved:
            return [("type", .string(String(describing: event)))]
        }
    }

    /// "selectExercise(shoulder_press)", "setWeight(17.5 lb)", or the command's name.
    static func label(_ command: WorkoutCommand) -> String {
        switch command {
        case .selectExercise(let id): return "selectExercise(\(id.rawValue))"
        case .setWeight(let weight): return "setWeight(\(weight.label))"
        default: return String(describing: command)
        }
    }

    private static func index(_ joint: LandmarkType) -> Int { jointIndex[joint] ?? -1 }

    private static func sortedByJoint<Value>(_ values: [LandmarkType: Value]) -> [(LandmarkType, Value)] {
        values.sorted { index($0.key) < index($1.key) }.map { ($0.key, $0.value) }
    }

    private static func sortedBySide<Value>(_ values: [BodySide: Value]) -> [(BodySide, Value)] {
        BodySide.allCases.compactMap { side in values[side].map { (side, $0) } }
    }
}
