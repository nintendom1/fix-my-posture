import SwiftUI
@testable import PostureAnalysisApp

enum WorkoutCameraFixtures {
    static let ids: Set<String> = [
        "camera-ready", "camera-active", "camera-paused", "camera-tip",
        "camera-rest-coach-muted", "camera-lost-mic-off", "camera-tilt"
    ]

    @MainActor
    static func screen(frameID: String) -> some View {
        WorkoutCameraDesignFixture(frameID: frameID)
    }

    static func viewState(frameID: String) -> WorkoutHUDViewState {
        let press = ShoulderPressExercise.definition()
        let row = DumbbellRowExercise.definition()
        let curl = HammerCurlExercise.definition()
        let triceps = TricepsExtensionExercise.definition()
        let exercises = [press, row, curl, triceps]
        let plan = WorkoutPlan(name: "Upper Body", items: exercises.map {
            WorkoutPlanItem(id: UUID(), exerciseID: $0.id, sets: 2, targetReps: $0.targetReps)
        })
        var session = WorkoutSession(exercises: exercises, initialExercise: nil, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)

        switch frameID {
        case "camera-ready":
            break
        case "camera-rest-coach-muted":
            _ = session.handle(.command(.start), at: 2)
            _ = session.handle(.command(.nextSet), at: 3)
        case "camera-paused":
            _ = session.handle(.command(.start), at: 2)
            addReferenceReps(to: &session)
            _ = session.handle(.command(.pause), at: 3)
        default:
            _ = session.handle(.command(.start), at: 2)
            if frameID != "camera-ready" { addReferenceReps(to: &session) }
        }

        let now: TimeInterval = frameID == "camera-rest-coach-muted" ? 35 : 4
        let isTilted = frameID == "camera-tilt"
        let hasPose = frameID != "camera-lost-mic-off"
        let activeTip: WorkoutVisualTip? = frameID == "camera-tip"
            ? WorkoutVisualTip(id: 1, kind: .corrective, text: "Press all the way up.")
            : nil
        let visualInputs = WorkoutVisualInputs(session: session, now: now,
                                               isPhoneTilted: isTilted,
                                               activeTip: activeTip,
                                               hasPose: hasPose)
        let visual = WorkoutVisualState.derive(visualInputs)
        let isMicMuted = frameID == "camera-lost-mic-off"
        let micStatus: VoiceStatus = isMicMuted ? .off : .listening
        let presentation = WorkoutHUDPresenter.derive(WorkoutHUDInputs(
            session: session,
            visual: visualInputs,
            voiceCommandsAvailable: !isMicMuted
        ))

        return WorkoutHUDViewState(
            presentation: presentation,
            visual: visual,
            exercise: WorkoutHUDInputs(session: session, visual: visualInputs,
                                       voiceCommandsAvailable: !isMicMuted).exercise,
            exerciseID: session.exerciseID,
            exerciseOptions: exercises.map { .init(id: $0.id, displayName: $0.displayName) },
            planName: session.plan?.name,
            isFollowingPlan: session.isFollowingPlan,
            repCount: session.repCount,
            sideReps: session.sideReps,
            currentWeights: [:],
            readings: [:],
            thresholds: [:],
            formReadings: [],
            isPhoneTilted: isTilted,
            micStatus: micStatus,
            isMicMuted: isMicMuted,
            heardPhrase: nil,
            isCoachMuted: frameID == "camera-rest-coach-muted",
            showsMeasurements: false
        )
    }

    private static func addReferenceReps(to session: inout WorkoutSession) {
        for rep in 1...6 {
            let time = 2 + Double(rep) * 0.1
            _ = session.handle(.repCompleted(RepEvent(epoch: session.analyzerEpoch,
                                                       timestamp: time,
                                                       sides: [.left, .right])), at: time)
        }
    }

    static func overlay() -> WorkoutOverlayState {
        let size = CGSize(width: 390, height: 360)
        let locations: [LandmarkType: CGPoint] = [
            .nose: CGPoint(x: 0.5, y: 0.91),
            .neck: CGPoint(x: 0.5, y: 0.79),
            .leftShoulder: CGPoint(x: 0.32, y: 0.72),
            .rightShoulder: CGPoint(x: 0.68, y: 0.72),
            .leftElbow: CGPoint(x: 0.27, y: 0.52),
            .rightElbow: CGPoint(x: 0.73, y: 0.52),
            .leftWrist: CGPoint(x: 0.34, y: 0.34),
            .rightWrist: CGPoint(x: 0.66, y: 0.34),
            .root: CGPoint(x: 0.5, y: 0.36),
            .leftHip: CGPoint(x: 0.42, y: 0.37),
            .rightHip: CGPoint(x: 0.58, y: 0.37)
        ]
        let poseLandmarks = Dictionary(uniqueKeysWithValues: locations.map { type, point in
            (type, Landmark(type: type,
                            normalizedLocation: point,
                            imageLocation: CGPoint(x: point.x * size.width, y: point.y * size.height),
                            confidence: 1))
        })
        let pose = BodyPose(landmarks: poseLandmarks, imageWidth: size.width, imageHeight: size.height)
        let joints = locations.mapValues { OverlayJoint(location: $0, isStale: false) }
        return WorkoutOverlayState(imageSize: size,
                                   joints: joints,
                                   segments: ShoulderPressExercise.definition().focusSegments,
                                   endPositionSides: [],
                                   pose: pose)
    }

    static func tip() -> CoachingTip {
        CoachingTip(id: 1, cue: .corrective(.init(rawValue: "press.full_extension"),
                                             "Press all the way up.", trigger: .perRep,
                                             priority: 1, joints: [.leftElbow, .rightElbow]))
    }
}

@MainActor
private struct WorkoutCameraDesignFixture: View {
    let frameID: String

    @State private var hudRects: [CGRect] = []

    private var state: WorkoutHUDViewState { WorkoutCameraFixtures.viewState(frameID: frameID) }
    private var exercise: ExerciseDefinition { ShoulderPressExercise.definition() }
    private var overlay: WorkoutOverlayState { WorkoutCameraFixtures.overlay() }
    private var metrics: GuideMetrics { GuideMetrics(upperArm: 82, forearm: 72) }
    private var coachingTip: CoachingTip? { frameID == "camera-tip" ? WorkoutCameraFixtures.tip() : nil }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreviewPattern().ignoresSafeArea()

                if state.visual.overlay == .ghostDemo {
                    WorkoutGhostOverlayView(overlay: overlay,
                                            metrics: metrics,
                                            motion: exercise.guide.motion,
                                            cameraView: exercise.cameraView)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                if state.visual.overlay == .repThresholds {
                    RepThresholdOverlayView(thresholds: state.thresholds, imageSize: overlay.imageSize)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                WorkoutJointOverlayView(overlay: overlay)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(state.visual.primary == .lost ? 0.2 : 1)

                WorkoutTipOverlayView(tip: coachingTip,
                                      protectedRects: WorkoutTipLayout.protectedRects(
                                        pose: overlay.pose,
                                        envelope: WorkoutTipLayout.envelopeRect(exercise.motionEnvelope,
                                                                               overlay: overlay,
                                                                               metrics: metrics,
                                                                               containerSize: geometry.size),
                                        containerSize: geometry.size),
                                      hudRects: hudRects,
                                      borderTint: coachingTip == nil ? nil : ColorTokens.palette().warning)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                WorkoutCameraScreen(state: state,
                                    scheduler: ManualScheduler(clock: ManualClock()),
                                    isVoiceOverRunning: { false },
                                    onIntent: { _ in })
            }
            .coordinateSpace(name: WorkoutCoachView.coordinateSpace)
            .onPreferenceChange(WorkoutHUDRects.self) { hudRects = $0 }
        }
        .environment(\.motionPolicy, .reduced)
    }
}

@MainActor
private struct CameraPreviewPattern: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(hex: 0x1A1720)))
            var offset = -size.height
            while offset <= size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: offset, y: size.height))
                stripe.addLine(to: CGPoint(x: offset + size.height, y: 0))
                context.stroke(stripe,
                               with: .color(Color(hex: 0x24202C)),
                               lineWidth: 10)
                offset += 28.284
            }
        }
    }
}
