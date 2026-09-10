import Foundation
import CoreGraphics

/// Result structure returned by `ReferencePoseGenerator` containing the final static reference pose and precomputed motion sequence.
public struct ReferenceGenerationResult {
    public let staticReference: ReferencePose
    public let motionSequence: [ReferencePose]
    public let isReplayAvailable: Bool
    public let unavailabilityReason: String?

    public init(
        staticReference: ReferencePose,
        motionSequence: [ReferencePose] = [],
        isReplayAvailable: Bool = true,
        unavailabilityReason: String? = nil
    ) {
        self.staticReference = staticReference
        self.motionSequence = motionSequence
        self.isReplayAvailable = isReplayAvailable
        self.unavailabilityReason = unavailabilityReason
    }
}

/// Estimator-independent subsystem that generates alignment reference geometry and constrained motion sequences.
public final class ReferencePoseGenerator {

    public init() {}

    /// Generates reference geometry and intermediate motion steps from an observed body pose, posture view, and reference profile.
    public func generateReference(
        for observedPose: BodyPose,
        view: PostureView,
        profile: PostureReferenceProfile
    ) -> ReferenceGenerationResult {
        let width = observedPose.imageWidth
        let height = observedPose.imageHeight

        guard width > 0 && height > 0 && !observedPose.landmarks.isEmpty else {
            let emptyRef = ReferencePose(unavailabilityReason: "No body landmarks detected for alignment reference.")
            return ReferenceGenerationResult(staticReference: emptyRef, isReplayAvailable: false, unavailabilityReason: emptyRef.unavailabilityReason)
        }

        // 1. Extract valid points meeting confidence threshold (>=0.3 or manually corrected) in pixel coordinates
        let points = extractValidPixelPoints(from: observedPose)

        // 2. Evaluate supported body regions
        let supportedRegions = evaluateSupportedRegions(points: points, view: view)

        if supportedRegions.isEmpty {
            let emptyRef = ReferencePose(unavailabilityReason: "Insufficient key landmarks to generate alignment reference.")
            return ReferenceGenerationResult(staticReference: emptyRef, isReplayAvailable: false, unavailabilityReason: emptyRef.unavailabilityReason)
        }

        // 3. Generate static reference pose (t = 1.0)
        guard let finalTarget = solveConstrainedPose(
            observedPoints: points,
            supportedRegions: supportedRegions,
            view: view,
            fraction: 1.0
        ) else {
            let emptyRef = ReferencePose(unavailabilityReason: "Constraint solver could not produce a valid reference geometry.")
            return ReferenceGenerationResult(staticReference: emptyRef, isReplayAvailable: false, unavailabilityReason: emptyRef.unavailabilityReason)
        }

        // Validate final target segment lengths against original
        guard validateSegmentLengths(original: points, solved: finalTarget, view: view) else {
            let emptyRef = ReferencePose(unavailabilityReason: "Reference geometry violated segment length constraints.")
            return ReferenceGenerationResult(staticReference: emptyRef, isReplayAvailable: false, unavailabilityReason: emptyRef.unavailabilityReason)
        }

        // 4. Precompute intermediate motion sequence for 2-second animation (10 steps)
        var sequence: [ReferencePose] = []
        var replayFailed = false

        let steps = 10
        for i in 1...steps {
            let fraction = Double(i) / Double(steps)
            if let solvedStep = solveConstrainedPose(observedPoints: points, supportedRegions: supportedRegions, view: view, fraction: fraction),
               validateSegmentLengths(original: points, solved: solvedStep, view: view) {
                let refStep = buildReferencePose(
                    jointLocations: solvedStep,
                    supportedRegions: supportedRegions,
                    view: view,
                    achievedChanges: buildAchievedChanges(original: points, solved: solvedStep, view: view, supportedRegions: supportedRegions)
                )
                sequence.append(refStep)
            } else {
                replayFailed = true
                break
            }
        }

        let captions = buildAchievedChanges(
            original: points,
            solved: finalTarget,
            view: view,
            supportedRegions: supportedRegions
        )

        let staticRef = buildReferencePose(
            jointLocations: finalTarget,
            supportedRegions: supportedRegions,
            view: view,
            achievedChanges: captions
        )

        if replayFailed {
            return ReferenceGenerationResult(
                staticReference: staticRef,
                motionSequence: [],
                isReplayAvailable: false,
                unavailabilityReason: "Replay animation unavailable due to motion constraint bounds."
            )
        } else {
            return ReferenceGenerationResult(
                staticReference: staticRef,
                motionSequence: sequence,
                isReplayAvailable: true,
                unavailabilityReason: nil
            )
        }
    }

    // MARK: - Private Helpers

    private func extractValidPixelPoints(from pose: BodyPose) -> [LandmarkType: CGPoint] {
        var points: [LandmarkType: CGPoint] = [:]
        for (type, lm) in pose.landmarks {
            if lm.confidence >= 0.3 || lm.isManuallyCorrected {
                points[type] = lm.imageLocation
            }
        }
        return points
    }

    private func evaluateSupportedRegions(points: [LandmarkType: CGPoint], view: PostureView) -> Set<BodyRegion> {
        var regions: Set<BodyRegion> = []

        switch view {
        case .front:
            // Front Legs: requires both ankles and both hips
            if points[.leftAnkle] != nil && points[.rightAnkle] != nil && points[.leftHip] != nil && points[.rightHip] != nil {
                regions.insert(.legs)
            }
            // Front Torso: requires both shoulders and both hips
            if points[.leftShoulder] != nil && points[.rightShoulder] != nil && points[.leftHip] != nil && points[.rightHip] != nil {
                regions.insert(.torso)
            }
            // Front Head: requires neck and at least one head/facial point
            if points[.neck] != nil && (points[.nose] != nil || points[.leftEye] != nil || points[.rightEye] != nil || points[.leftEar] != nil || points[.rightEar] != nil) {
                regions.insert(.head)
            }
            // Arms: evaluated if shoulders exist
            if points[.leftShoulder] != nil && points[.rightShoulder] != nil {
                regions.insert(.arms)
            }

        case .leftSide:
            // Left Side coherent chain
            if points[.leftAnkle] != nil && points[.leftKnee] != nil && points[.leftHip] != nil {
                regions.insert(.legs)
            }
            if points[.leftHip] != nil && points[.leftShoulder] != nil {
                regions.insert(.torso)
            }
            if (points[.leftEar] != nil || points[.nose] != nil) && (points[.leftShoulder] != nil || points[.neck] != nil) {
                regions.insert(.head)
            }
            if points[.leftShoulder] != nil {
                regions.insert(.arms)
            }

        case .rightSide:
            // Right Side coherent chain
            if points[.rightAnkle] != nil && points[.rightKnee] != nil && points[.rightHip] != nil {
                regions.insert(.legs)
            }
            if points[.rightHip] != nil && points[.rightShoulder] != nil {
                regions.insert(.torso)
            }
            if (points[.rightEar] != nil || points[.nose] != nil) && (points[.rightShoulder] != nil || points[.neck] != nil) {
                regions.insert(.head)
            }
            if points[.rightShoulder] != nil {
                regions.insert(.arms)
            }
        }

        return regions
    }

    // MARK: - Constrained Geometry Solver

    private func solveConstrainedPose(
        observedPoints: [LandmarkType: CGPoint],
        supportedRegions: Set<BodyRegion>,
        view: PostureView,
        fraction: Double
    ) -> [LandmarkType: CGPoint]? {
        var solved = observedPoints

        switch view {
        case .front:
            solveFrontView(solved: &solved, observed: observedPoints, supportedRegions: supportedRegions, fraction: fraction)
        case .leftSide:
            solveSideView(solved: &solved, observed: observedPoints, side: .left, supportedRegions: supportedRegions, fraction: fraction)
        case .rightSide:
            solveSideView(solved: &solved, observed: observedPoints, side: .right, supportedRegions: supportedRegions, fraction: fraction)
        }

        return solved
    }

    private enum Side { case left, right }

    private func solveFrontView(
        solved: inout [LandmarkType: CGPoint],
        observed: [LandmarkType: CGPoint],
        supportedRegions: Set<BodyRegion>,
        fraction: Double
    ) {
        // 1. Planted Ankles remain fixed
        guard let lAnkle = observed[.leftAnkle], let rAnkle = observed[.rightAnkle] else { return }
        let ankleMidX = (lAnkle.x + rAnkle.x) / 2.0

        // 2. Hips & Torso
        if supportedRegions.contains(.torso),
           let lHipObs = observed[.leftHip], let rHipObs = observed[.rightHip],
           let lShObs = observed[.leftShoulder], let rShObs = observed[.rightShoulder] {

            let hipWidth = hypot(rHipObs.x - lHipObs.x, rHipObs.y - lHipObs.y)
            let shWidth = hypot(rShObs.x - lShObs.x, rShObs.y - lShObs.y)

            // Target hip level y
            let targetHipY = (lHipObs.y + rHipObs.y) / 2.0
            let targetHipCenterX = ankleMidX

            // Move hip center toward target hip center X and level Y
            let currentHipCenterX = (lHipObs.x + rHipObs.x) / 2.0
            let currentHipCenterY = (lHipObs.y + rHipObs.y) / 2.0

            let newHipCenterX = currentHipCenterX + (targetHipCenterX - currentHipCenterX) * fraction
            let newHipCenterY = currentHipCenterY + (targetHipY - currentHipCenterY) * fraction

            let newLHip = CGPoint(x: newHipCenterX - hipWidth / 2.0, y: newHipCenterY)
            let newRHip = CGPoint(x: newHipCenterX + hipWidth / 2.0, y: newHipCenterY)

            solved[.leftHip] = newLHip
            solved[.rightHip] = newRHip

            // Target shoulder level y
            let targetShY = (lShObs.y + rShObs.y) / 2.0
            let targetShCenterX = ankleMidX

            let currentShCenterX = (lShObs.x + rShObs.x) / 2.0
            let currentShCenterY = (lShObs.y + rShObs.y) / 2.0

            let newShCenterX = currentShCenterX + (targetShCenterX - currentShCenterX) * fraction
            let newShCenterY = currentShCenterY + (targetShY - currentShCenterY) * fraction

            let newLSh = CGPoint(x: newShCenterX - shWidth / 2.0, y: newShCenterY)
            let newRSh = CGPoint(x: newShCenterX + shWidth / 2.0, y: newShCenterY)

            solved[.leftShoulder] = newLSh
            solved[.rightShoulder] = newRSh

            // Neck / Root
            if let neckObs = observed[.neck] {
                let neckOffset = neckObs - CGPoint(x: currentShCenterX, y: currentShCenterY)
                solved[.neck] = CGPoint(x: newShCenterX, y: newShCenterY) + neckOffset
            }
            if let rootObs = observed[.root] {
                let rootOffset = rootObs - CGPoint(x: currentHipCenterX, y: currentHipCenterY)
                solved[.root] = CGPoint(x: newHipCenterX, y: newHipCenterY) + rootOffset
            }
        }

        // 3. Legs
        if supportedRegions.contains(.legs),
           let newLHip = solved[.leftHip], let newRHip = solved[.rightHip] {

            // Adjust knees to lie on hip-ankle line while preserving hip-knee and knee-ankle segment lengths
            if let lKneeObs = observed[.leftKnee], let lHipObs = observed[.leftHip] {
                let lenHipKnee = hypot(lKneeObs.x - lHipObs.x, lKneeObs.y - lHipObs.y)
                let lenKneeAnkle = hypot(lAnkle.x - lKneeObs.x, lAnkle.y - lKneeObs.y)
                let solvedLKnee = solveKneePosition(hip: newLHip, ankle: lAnkle, lenHipKnee: lenHipKnee, lenKneeAnkle: lenKneeAnkle, observedKnee: lKneeObs, fraction: fraction)
                solved[.leftKnee] = solvedLKnee
            }

            if let rKneeObs = observed[.rightKnee], let rHipObs = observed[.rightHip] {
                let lenHipKnee = hypot(rKneeObs.x - rHipObs.x, rKneeObs.y - rHipObs.y)
                let lenKneeAnkle = hypot(rAnkle.x - rKneeObs.x, rAnkle.y - rKneeObs.y)
                let solvedRKnee = solveKneePosition(hip: newRHip, ankle: rAnkle, lenHipKnee: lenHipKnee, lenKneeAnkle: lenKneeAnkle, observedKnee: rKneeObs, fraction: fraction)
                solved[.rightKnee] = solvedRKnee
            }
        }

        // 4. Head
        if supportedRegions.contains(.head), let neckSolved = solved[.neck] ?? solved[.leftShoulder] {
            let headPoints: [LandmarkType] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
            let referenceHeadOrigin = observed[.neck] ?? observed[.leftShoulder] ?? .zero

            let headShift = neckSolved - referenceHeadOrigin

            // Level eyes and ears if both pair members exist
            var eyeAngleCorrection: CGFloat = 0.0
            if let lEye = observed[.leftEye], let rEye = observed[.rightEye] {
                let currentAngle = atan2(rEye.y - lEye.y, rEye.x - lEye.x)
                eyeAngleCorrection = -currentAngle * CGFloat(fraction)
            }

            let headCenterObs: CGPoint
            if let nose = observed[.nose] { headCenterObs = nose }
            else if let lEye = observed[.leftEye], let rEye = observed[.rightEye] { headCenterObs = CGPoint(x: (lEye.x + rEye.x)/2, y: (lEye.y + rEye.y)/2) }
            else { headCenterObs = referenceHeadOrigin }

            for hPt in headPoints {
                if let obsPt = observed[hPt] {
                    var pt = obsPt + headShift
                    if eyeAngleCorrection != 0 {
                        pt = rotatePoint(pt, around: headCenterObs + headShift, by: eyeAngleCorrection)
                    }
                    // Align horizontal center over ankleMidX
                    let dxToCenter = (ankleMidX - (headCenterObs.x + headShift.x)) * CGFloat(fraction)
                    pt.x += dxToCenter
                    solved[hPt] = pt
                }
            }
        }

        // 5. Arms
        if supportedRegions.contains(.arms) {
            if let lShObs = observed[.leftShoulder], let lShNew = solved[.leftShoulder] {
                let shift = lShNew - lShObs
                if let lElbowObs = observed[.leftElbow] { solved[.leftElbow] = lElbowObs + shift }
                if let lWristObs = observed[.leftWrist] { solved[.leftWrist] = lWristObs + shift }
            }
            if let rShObs = observed[.rightShoulder], let rShNew = solved[.rightShoulder] {
                let shift = rShNew - rShObs
                if let rElbowObs = observed[.rightElbow] { solved[.rightElbow] = rElbowObs + shift }
                if let rWristObs = observed[.rightWrist] { solved[.rightWrist] = rWristObs + shift }
            }
        }
    }

    private func solveSideView(
        solved: inout [LandmarkType: CGPoint],
        observed: [LandmarkType: CGPoint],
        side: Side,
        supportedRegions: Set<BodyRegion>,
        fraction: Double
    ) {
        let ankleKey: LandmarkType = (side == .left) ? .leftAnkle : .rightAnkle
        let kneeKey: LandmarkType = (side == .left) ? .leftKnee : .rightKnee
        let hipKey: LandmarkType = (side == .left) ? .leftHip : .rightHip
        let shoulderKey: LandmarkType = (side == .left) ? .leftShoulder : .rightShoulder
        let earKey: LandmarkType = (side == .left) ? .leftEar : .rightEar

        guard let anklePt = observed[ankleKey] else { return }

        // Visible ankle remains planted
        solved[ankleKey] = anklePt

        // Target x vertical stack = anklePt.x
        let targetX = anklePt.x

        // 1. Hip
        if let hipObs = observed[hipKey] {
            let lenHipAnkle = hypot(hipObs.x - anklePt.x, hipObs.y - anklePt.y)

            let currentHipX = hipObs.x
            let newHipX = currentHipX + (targetX - currentHipX) * CGFloat(fraction)

            // Calculate dy to preserve lenHipAnkle
            let dx = abs(newHipX - anklePt.x)
            let dy = sqrt(max(0, lenHipAnkle * lenHipAnkle - dx * dx))
            let newHipY = anklePt.y - dy // Y goes down in top-left pixel space

            let newHip = CGPoint(x: newHipX, y: newHipY)
            solved[hipKey] = newHip

            // 2. Knee
            if supportedRegions.contains(.legs), let kneeObs = observed[kneeKey] {
                let lenHipKnee = hypot(kneeObs.x - hipObs.x, kneeObs.y - hipObs.y)
                let lenKneeAnkle = hypot(anklePt.x - kneeObs.x, anklePt.y - kneeObs.y)

                let solvedKnee = solveKneePosition(hip: newHip, ankle: anklePt, lenHipKnee: lenHipKnee, lenKneeAnkle: lenKneeAnkle, observedKnee: kneeObs, fraction: fraction)
                solved[kneeKey] = solvedKnee
            }
        }

        // 3. Shoulder
        if supportedRegions.contains(.torso), let hipNew = solved[hipKey], let shObs = observed[shoulderKey], let hipObs = observed[hipKey] {
            let lenTorso = hypot(shObs.x - hipObs.x, shObs.y - hipObs.y)

            let currentShX = shObs.x
            let newShX = currentShX + (targetX - currentShX) * CGFloat(fraction)

            let dx = abs(newShX - hipNew.x)
            let dy = sqrt(max(0, lenTorso * lenTorso - dx * dx))
            let newShY = hipNew.y - dy

            let newSh = CGPoint(x: newShX, y: newShY)
            solved[shoulderKey] = newSh

            if let neckObs = observed[.neck] {
                let neckShift = newSh - shObs
                solved[.neck] = neckObs + neckShift
            }
        }

        // 4. Ear / Head
        if supportedRegions.contains(.head), let shNew = solved[shoulderKey] ?? solved[hipKey], let shObs = observed[shoulderKey] ?? observed[hipKey] {
            if let earObs = observed[earKey] {
                let lenEarSh = hypot(earObs.x - shObs.x, earObs.y - shObs.y)
                let newEarX = earObs.x + (targetX - earObs.x) * CGFloat(fraction)
                let dx = abs(newEarX - shNew.x)
                let dy = sqrt(max(0, lenEarSh * lenEarSh - dx * dx))
                let newEarY = shNew.y - dy
                solved[earKey] = CGPoint(x: newEarX, y: newEarY)
            }

            if let noseObs = observed[.nose] {
                let shift = shNew - shObs
                solved[.nose] = noseObs + shift
            }
        }

        // 5. Arm
        if supportedRegions.contains(.arms), let shObs = observed[shoulderKey], let shNew = solved[shoulderKey] {
            let shift = shNew - shObs
            let elbowKey: LandmarkType = (side == .left) ? .leftElbow : .rightElbow
            let wristKey: LandmarkType = (side == .left) ? .leftWrist : .rightWrist

            if let elbowObs = observed[elbowKey] { solved[elbowKey] = elbowObs + shift }
            if let wristObs = observed[wristKey] { solved[wristKey] = wristObs + shift }
        }
    }

    private func solveKneePosition(
        hip: CGPoint,
        ankle: CGPoint,
        lenHipKnee: CGFloat,
        lenKneeAnkle: CGFloat,
        observedKnee: CGPoint,
        fraction: Double
    ) -> CGPoint {
        // Distance between hip and ankle
        let d = hypot(ankle.x - hip.x, ankle.y - hip.y)
        guard d > 0 else { return observedKnee }

        // Straight target alignment: knee lies on line segment hip -> ankle
        let targetRatio = lenHipKnee / (lenHipKnee + lenKneeAnkle)
        let straightKneeX = hip.x + (ankle.x - hip.x) * targetRatio
        let straightKneeY = hip.y + (ankle.y - hip.y) * targetRatio

        let targetKnee = CGPoint(x: straightKneeX, y: straightKneeY)

        // Interpolate knee towards target
        let curKneeX = observedKnee.x + (targetKnee.x - observedKnee.x) * CGFloat(fraction)
        let curKneeY = observedKnee.y + (targetKnee.y - observedKnee.y) * CGFloat(fraction)

        // Rescale distance to preserve segment lengths relative to hip and ankle
        let vecH = CGPoint(x: curKneeX - hip.x, y: curKneeY - hip.y)
        let distH = hypot(vecH.x, vecH.y)
        if distH > 0 {
            return CGPoint(
                x: hip.x + (vecH.x / distH) * lenHipKnee,
                y: hip.y + (vecH.y / distH) * lenHipKnee
            )
        }

        return targetKnee
    }

    private func validateSegmentLengths(
        original: [LandmarkType: CGPoint],
        solved: [LandmarkType: CGPoint],
        view: PostureView
    ) -> Bool {
        let maxToleranceRatio: CGFloat = 0.05 // Max 5% segment length deviation permitted

        let pairsToValidate: [(LandmarkType, LandmarkType)]
        switch view {
        case .front:
            pairsToValidate = [
                (.leftShoulder, .rightShoulder),
                (.leftHip, .rightHip),
                (.leftHip, .leftKnee),
                (.leftKnee, .leftAnkle),
                (.rightHip, .rightKnee),
                (.rightKnee, .rightAnkle),
                (.leftShoulder, .leftHip),
                (.rightShoulder, .rightHip)
            ]
        case .leftSide:
            pairsToValidate = [
                (.leftHip, .leftKnee),
                (.leftKnee, .leftAnkle),
                (.leftShoulder, .leftHip),
                (.leftEar, .leftShoulder)
            ]
        case .rightSide:
            pairsToValidate = [
                (.rightHip, .rightKnee),
                (.rightKnee, .rightAnkle),
                (.rightShoulder, .rightHip),
                (.rightEar, .rightShoulder)
            ]
        }

        for (jA, jB) in pairsToValidate {
            if let origA = original[jA], let origB = original[jB],
               let solvA = solved[jA], let solvB = solved[jB] {
                let origLen = hypot(origB.x - origA.x, origB.y - origA.y)
                let solvLen = hypot(solvB.x - solvA.x, solvB.y - solvA.y)

                if origLen > 5.0 {
                    let diffRatio = abs(solvLen - origLen) / origLen
                    if diffRatio > maxToleranceRatio {
                        return false
                    }
                }
            }
        }

        return true
    }

    private func buildAchievedChanges(
        original: [LandmarkType: CGPoint],
        solved: [LandmarkType: CGPoint],
        view: PostureView,
        supportedRegions: Set<BodyRegion>
    ) -> [String] {
        var changes: [String] = []

        switch view {
        case .front:
            if supportedRegions.contains(.torso) {
                if let origLSh = original[.leftShoulder], let origRSh = original[.rightShoulder] {
                    let origDiff = abs(origLSh.y - origRSh.y)
                    if origDiff > 2.0 {
                        changes.append("Shoulder reference: closer to level.")
                    }
                }
                if let origLHip = original[.leftHip], let origRHip = original[.rightHip] {
                    let origDiff = abs(origLHip.y - origRHip.y)
                    if origDiff > 2.0 {
                        changes.append("Hip reference: closer to level.")
                    }
                }
                changes.append("Torso & head reference: centered over ankle midpoint.")
            }
            if supportedRegions.contains(.legs) {
                changes.append("Knee alignment reference: guided toward hip-ankle line.")
            }

        case .leftSide, .rightSide:
            if supportedRegions.contains(.torso) || supportedRegions.contains(.head) {
                changes.append("Upper body reference: guided toward vertical ear-shoulder-hip stack over ankle.")
            }
            if supportedRegions.contains(.legs) {
                changes.append("Leg alignment reference: straighter hip-knee-ankle chain over visible ankle.")
            }
        }

        return changes
    }

    private func buildReferencePose(
        jointLocations: [LandmarkType: CGPoint],
        supportedRegions: Set<BodyRegion>,
        view: PostureView,
        achievedChanges: [String]
    ) -> ReferencePose {
        var connections: [ConnectionPair] = []

        let candidateConnections: [(LandmarkType, LandmarkType)]
        switch view {
        case .front:
            candidateConnections = BodyPose.connections
        case .leftSide:
            candidateConnections = [
                (.leftEar, .leftShoulder),
                (.leftShoulder, .leftHip),
                (.leftHip, .leftKnee),
                (.leftKnee, .leftAnkle),
                (.leftShoulder, .leftElbow),
                (.leftElbow, .leftWrist)
            ]
        case .rightSide:
            candidateConnections = [
                (.rightEar, .rightShoulder),
                (.rightShoulder, .rightHip),
                (.rightHip, .rightKnee),
                (.rightKnee, .rightAnkle),
                (.rightShoulder, .rightElbow),
                (.rightElbow, .rightWrist)
            ]
        }

        for (jA, jB) in candidateConnections {
            if jointLocations[jA] != nil && jointLocations[jB] != nil {
                connections.append(ConnectionPair(jA, jB))
            }
        }

        return ReferencePose(
            jointLocations: jointLocations,
            connections: connections,
            supportedRegions: supportedRegions,
            achievedChanges: achievedChanges,
            unavailabilityReason: nil
        )
    }

    private func rotatePoint(_ point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGPoint(
            x: center.x + dx * cosA - dy * sinA,
            y: center.y + dx * sinA + dy * cosA
        )
    }
}

// Point arithmetic extension helpers
private extension CGPoint {
    static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        CGPoint(x: left.x + right.x, y: left.y + right.y)
    }
    static func - (left: CGPoint, right: CGPoint) -> CGPoint {
        CGPoint(x: left.x - right.x, y: left.y - right.y)
    }
}
