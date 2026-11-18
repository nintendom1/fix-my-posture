import CoreGraphics
import Foundation

/// The single most useful framing instruction, worded relative to the user.
enum FramingGuidance: String, Equatable {
    case stepIntoView
    case stepBack
    case stepBackSideRoom
    case moreHeadroom
    case moveLeft
    case moveRight
    case stepIntoViewSideOn
    case stepBackSideOn
    case stepIntoViewSideFullBody
    case stepBackSideFullBody
    case stepBackFullBody
    case stepIntoViewFloor
    case stepBackFloor
    case stepIntoViewLyingSide
    case stepBackLyingSide
    case movePhoneFartherFloor

    static func needsFullBodySideView(requiredJoints: Set<LandmarkType>,
                                      anyOfRequiredJoints: [Set<LandmarkType>]) -> Bool {
        requiredJoints.contains(.leftAnkle) || requiredJoints.contains(.rightAnkle)
            || anyOfRequiredJoints.contains { $0.contains(.leftAnkle) || $0.contains(.rightAnkle) }
    }

    /// The line used when an exercise needs the user to enter the active camera view.
    static func stepIntoViewGuidance(cameraView: ExerciseCameraView, requiredJoints: Set<LandmarkType>,
                                     anyOfRequiredJoints: [Set<LandmarkType>]) -> FramingGuidance {
        let needsFullBody = needsFullBodySideView(requiredJoints: requiredJoints,
                                                  anyOfRequiredJoints: anyOfRequiredJoints)
        switch cameraView {
        case .front: return .stepIntoView
        case .side: return needsFullBody ? .stepIntoViewSideFullBody : .stepIntoViewSideOn
        case .floor: return .stepIntoViewFloor
        case .lyingSide: return .stepIntoViewLyingSide
        }
    }

    var spokenText: String {
        switch self {
        case .stepIntoView: return "Step into view, facing the phone."
        case .stepBack: return "Step back until both arms and shoulders are in view."
        case .stepBackSideRoom: return "Step back so your arms have room out to the sides."
        case .stepIntoViewSideOn: return "Step into view, standing side-on to the phone."
        case .stepBackSideOn: return "Step back until your arm and head are in view."
        case .stepIntoViewSideFullBody: return "Stand side-on to the phone with your whole body in view."
        case .stepBackSideFullBody: return "Step back until your whole body is in view, still side-on."
        case .stepBackFullBody: return "Step back until your whole body is in view, head to feet."
        case .stepIntoViewFloor: return "Get into a plank facing the phone."
        case .stepBackFloor: return "Move the phone back until your arms and shoulders are in view."
        case .stepIntoViewLyingSide: return "Lie on your back side-on to the phone."
        case .stepBackLyingSide: return "Lie on your back side-on to the phone, knees bent, with your whole body in view."
        case .movePhoneFartherFloor: return "Move the phone farther from your hands, so you stay in view at the bottom."
        case .moreHeadroom: return "Step back a little more so there's room above your hands."
        case .moveLeft: return "Move a little to your left."
        case .moveRight: return "Move a little to your right."
        }
    }

    var shortText: String {
        switch self {
        case .stepIntoView: return "Step into view"
        case .stepBack: return "Step back: show both arms"
        case .stepBackSideRoom: return "Step back: room for your arms"
        case .stepIntoViewSideOn: return "Step into view, side-on"
        case .stepBackSideOn: return "Step back: show your arm"
        case .stepIntoViewSideFullBody: return "Stand side-on, show your whole body"
        case .stepBackSideFullBody: return "Step back: show whole body, side-on"
        case .stepBackFullBody: return "Step back: show your whole body"
        case .stepIntoViewFloor: return "Get into a plank facing the phone"
        case .stepBackFloor: return "Move the phone back: show your arms"
        case .stepIntoViewLyingSide: return "Lie down, side-on"
        case .stepBackLyingSide: return "Step back: show your whole body"
        case .movePhoneFartherFloor: return "Move the phone farther away"
        case .moreHeadroom: return "Step back: leave room overhead"
        case .moveLeft: return "Move a little to your left"
        case .moveRight: return "Move a little to your right"
        }
    }
}

struct FramingStatus: Equatable {
    /// Required joints have been steadily visible; counting may run.
    var isReliable: Bool
    var guidance: FramingGuidance?

    static let lost = FramingStatus(isReliable: false, guidance: nil)
}

/// Prototype framing thresholds; tune on device.
struct FramingConfiguration: Codable {
    var minimumConfidence: Double = 0.4
    /// Required joints must stay visible this long before tracking is reliable.
    var reliableAfter: TimeInterval = 0.6
    /// Tracking becomes unreliable after required joints are missing this long.
    var unreliableAfter: TimeInterval = 0.3
    /// Fraction of image height kept clear above the overhead reach.
    var headroomMargin: CGFloat = 0.02
    /// Allowed body-center offset from the image center, as a fraction of image width.
    var centerTolerance: CGFloat = 0.17
    /// Fewer confident joints than this means nobody is in view.
    var minimumBodyJoints = 3
    /// A normalized phone-distance measurement must fall this far below its limit to clear the warning, so values
    /// near a boundary don't flicker.
    var shoulderSpanClearance: CGFloat = 0.02
}

/// The joints one camera view needs in sight: every required joint, plus one full alternative set when there are any.
struct FramingRequirement: Equatable {
    let requiredJoints: Set<LandmarkType>
    let anyOfRequiredJoints: [Set<LandmarkType>]
}

/// Decides tracking reliability and framing guidance from an exercise's required joints.
struct FramingEvaluator {
    let requiredJoints: Set<LandmarkType>
    /// When not empty, one of these sets must also be fully visible.
    let anyOfRequiredJoints: [Set<LandmarkType>]
    /// Overhead room needed above the shoulders, in measured arm lengths; nil skips the check.
    let headroomArmLengths: CGFloat?
    /// Horizontal room needed at each shoulder, in measured arm lengths; nil skips the check.
    let sideroomArmLengths: CGFloat?
    /// Widest the shoulders may span, as a fraction of image width, before the phone is too close; nil skips the
    /// check. Guidance only: it holds setup but never affects reliability, so a set in progress keeps counting.
    let maximumShoulderSpan: CGFloat?
    /// Lowest in-frame position allowed for either wrist, as a fraction of image height from the top; lower asks for
    /// the phone farther away, and nil skips the check. Guidance only, like the shoulder span.
    let maximumWristHeightFraction: CGFloat?
    /// Shoulders that count as visible below `configuration.minimumConfidence` while both arms are clearly seen, so
    /// a face-down push-up bottom stays reliable; nil keeps every required joint at the usual confidence. The
    /// references live as long as the analyzer's: `reset()` keeps them, and `resetSupportedShoulders()` clears them.
    let supportedShoulders: SupportedShoulderRule?
    let centersInFrame: Bool
    let cameraView: ExerciseCameraView
    let configuration: FramingConfiguration
    private var shoulderSupport: SupportedShoulders
    private var presentSince: TimeInterval?
    private var lastPresent: TimeInterval?
    private(set) var isReliable = false
    private var isShoulderSpanTooWide = false
    private var areWristsTooLow = false
    private var isPhoneTooClose: Bool { isShoulderSpanTooWide || areWristsTooLow }

    private var needsFullBodySideView: Bool {
        FramingGuidance.needsFullBodySideView(requiredJoints: requiredJoints,
                                              anyOfRequiredJoints: anyOfRequiredJoints)
    }

    init(requiredJoints: Set<LandmarkType>, anyOfRequiredJoints: [Set<LandmarkType>] = [], headroomArmLengths: CGFloat?,
         sideroomArmLengths: CGFloat? = nil, maximumShoulderSpan: CGFloat? = nil,
         maximumWristHeightFraction: CGFloat? = nil, supportedShoulders: SupportedShoulderRule? = nil,
         centersInFrame: Bool = true, cameraView: ExerciseCameraView = .front,
         configuration: FramingConfiguration = FramingConfiguration()) {
        self.requiredJoints = requiredJoints
        self.anyOfRequiredJoints = anyOfRequiredJoints
        self.headroomArmLengths = headroomArmLengths
        self.sideroomArmLengths = sideroomArmLengths
        self.maximumShoulderSpan = maximumShoulderSpan
        self.maximumWristHeightFraction = maximumWristHeightFraction
        self.supportedShoulders = supportedShoulders
        self.centersInFrame = centersInFrame
        self.cameraView = cameraView
        self.configuration = configuration
        shoulderSupport = SupportedShoulders(rule: supportedShoulders, minimumConfidence: configuration.minimumConfidence)
    }

    /// `alsoAccepting` lists other views' requirements that count as present too, such as every view of the exercise
    /// while the user turns between them.
    mutating func evaluate(_ frame: PoseFrame, alsoAccepting alternatives: [FramingRequirement] = []) -> FramingStatus {
        let time = frame.timestamp
        let supported = shoulderSupport.update(frame)
        func visible(_ joints: Set<LandmarkType>) -> Bool {
            joints.allSatisfy {
                supported.contains($0) || frame.point($0, minimumConfidence: configuration.minimumConfidence) != nil
            }
        }
        func satisfied(_ required: Set<LandmarkType>, _ anyOf: [Set<LandmarkType>]) -> Bool {
            visible(required) && (anyOf.isEmpty || anyOf.contains(where: visible))
        }
        let requiredPresent = satisfied(requiredJoints, anyOfRequiredJoints)
            || alternatives.contains { satisfied($0.requiredJoints, $0.anyOfRequiredJoints) }
        updatePhoneDistance(frame)
        let present = requiredPresent && !lacksSideRoom(frame)
        if present {
            let since = presentSince ?? time
            presentSince = since
            lastPresent = time
            if !isReliable, time - since >= configuration.reliableAfter { isReliable = true }
        } else {
            presentSince = nil
            if isReliable, time - (lastPresent ?? time) >= configuration.unreliableAfter { isReliable = false }
        }
        return FramingStatus(isReliable: isReliable, guidance: guidance(for: frame, requiredPresent: requiredPresent))
    }

    /// Starts a freshly rebuilt view evaluator as reliable when its required joints, or one of `alternatives` as
    /// `evaluate` accepts them, are already visible. Otherwise the regular `reliableAfter` delay remains in effect.
    mutating func prime(with frame: PoseFrame, alsoAccepting alternatives: [FramingRequirement] = []) {
        func visible(_ joints: Set<LandmarkType>) -> Bool {
            joints.allSatisfy { frame.point($0, minimumConfidence: configuration.minimumConfidence) != nil }
        }
        func satisfied(_ required: Set<LandmarkType>, _ anyOf: [Set<LandmarkType>]) -> Bool {
            visible(required) && (anyOf.isEmpty || anyOf.contains(where: visible))
        }
        let requiredPresent = satisfied(requiredJoints, anyOfRequiredJoints)
            || alternatives.contains { satisfied($0.requiredJoints, $0.anyOfRequiredJoints) }
        guard requiredPresent else { return }
        presentSince = frame.timestamp
        lastPresent = frame.timestamp
        isReliable = true
    }

    /// Carries reliability over from the evaluator of the same exercise's previous camera view, so a view change
    /// neither loses framing nor restarts its grace: reliable framing stays reliable until this view's requirements, or
    /// the accepted alternatives, have been missing for `unreliableAfter`.
    mutating func continueReliability(from previous: FramingEvaluator) {
        presentSince = previous.presentSince
        lastPresent = previous.lastPresent
        isReliable = previous.isReliable
    }

    mutating func reset() {
        presentSince = nil
        lastPresent = nil
        isReliable = false
        isShoulderSpanTooWide = false
        areWristsTooLow = false
    }

    /// Forgets the supported-shoulder references, as a new analyzer does, so both decide alike on every frame.
    mutating func resetSupportedShoulders() {
        shoulderSupport.reset()
    }

    /// Distance guidance latches each configured measurement until it clears its hysteresis range. Missing joints
    /// keep the last answer; missing required joints have their own guidance.
    private mutating func updatePhoneDistance(_ frame: PoseFrame) {
        let confidence = configuration.minimumConfidence
        if let maximumShoulderSpan, frame.pose.imageWidth > 0,
           let left = frame.point(.leftShoulder, minimumConfidence: confidence),
           let right = frame.point(.rightShoulder, minimumConfidence: confidence) {
            let span = hypot(left.x - right.x, left.y - right.y) / frame.pose.imageWidth
            if span > maximumShoulderSpan {
                isShoulderSpanTooWide = true
            } else if span < maximumShoulderSpan - configuration.shoulderSpanClearance {
                isShoulderSpanTooWide = false
            }
        }

        if let maximumWristHeightFraction, frame.pose.imageHeight > 0,
           let left = frame.point(.leftWrist, minimumConfidence: confidence),
           let right = frame.point(.rightWrist, minimumConfidence: confidence) {
            let wristHeight = max(left.y, right.y) / frame.pose.imageHeight
            if wristHeight > maximumWristHeightFraction {
                areWristsTooLow = true
            } else if wristHeight < maximumWristHeightFraction - configuration.shoulderSpanClearance {
                areWristsTooLow = false
            }
        }
    }

    private func guidance(for frame: PoseFrame, requiredPresent: Bool) -> FramingGuidance? {
        let confidence = configuration.minimumConfidence
        let visible = frame.pose.landmarks.values.filter { $0.confidence >= confidence }
        let sideOn = cameraView == .side
        let floor = cameraView == .floor
        guard visible.count >= configuration.minimumBodyJoints else {
            return FramingGuidance.stepIntoViewGuidance(cameraView: cameraView, requiredJoints: requiredJoints,
                                                        anyOfRequiredJoints: anyOfRequiredJoints)
        }
        guard requiredPresent else {
            if cameraView == .lyingSide { return .stepBackLyingSide }
            if sideOn { return needsFullBodySideView ? .stepBackSideFullBody : .stepBackSideOn }
            if floor { return .stepBackFloor }
            return requiredJoints.contains(.leftAnkle) || requiredJoints.contains(.rightAnkle) ? .stepBackFullBody : .stepBack
        }

        if let headroomArmLengths {
            let arms = BodySide.allCases.compactMap { ArmGeometry.arm($0, in: frame, minimumConfidence: confidence) }
            if let reach = arms.map(\.armLength).max(),
               let shoulderTop = arms.map(\.shoulder.y).min(),
               shoulderTop - headroomArmLengths * reach < configuration.headroomMargin * frame.pose.imageHeight {
                return .moreHeadroom
            }
        }

        if lacksSideRoom(frame) { return .stepBackSideRoom }

        if isPhoneTooClose { return .movePhoneFartherFloor }

        if cameraView == .lyingSide || !centersInFrame { return nil }

        let anchors = [LandmarkType.leftShoulder, .rightShoulder, .leftHip, .rightHip]
            .compactMap { frame.point($0, minimumConfidence: confidence) }
        guard !anchors.isEmpty, frame.pose.imageWidth > 0 else { return nil }
        let centerX = anchors.map(\.x).reduce(0, +) / CGFloat(anchors.count) / frame.pose.imageWidth
        // Unmirrored front-camera x grows toward the user's left, so a small x means
        // the user stands to their right of center and should move left.
        if centerX < 0.5 - configuration.centerTolerance { return .moveLeft }
        if centerX > 0.5 + configuration.centerTolerance { return .moveRight }
        return nil
    }

    private func lacksSideRoom(_ frame: PoseFrame) -> Bool {
        guard let sideroomArmLengths, frame.pose.imageWidth > 0 else { return false }
        let confidence = configuration.minimumConfidence
        let margin = configuration.headroomMargin * frame.pose.imageWidth
        let requiredRoom = BodySide.allCases.compactMap {
            ArmGeometry.arm($0, in: frame, minimumConfidence: confidence)
        }.contains { arm in
            let nearestEdge = min(arm.shoulder.x, frame.pose.imageWidth - arm.shoulder.x)
            return nearestEdge < sideroomArmLengths * arm.armLength + margin
        }
        return requiredRoom
    }
}
