import Foundation
import CoreGraphics

public struct ReferenceGenerationResult {
    public let staticReference: ReferencePose
    public let motionSequence: [ReferencePose]
    public let isReplayAvailable: Bool
    public let unavailabilityReason: String?

    public init(staticReference: ReferencePose, motionSequence: [ReferencePose] = [], isReplayAvailable: Bool = true, unavailabilityReason: String? = nil) {
        self.staticReference = staticReference
        self.motionSequence = motionSequence
        self.isReplayAvailable = isReplayAvailable
        self.unavailabilityReason = unavailabilityReason
    }
}

/// Generates an illustrative pose in image-pixel space while preserving observed
/// proportions and any available foot anchors.
public final class ReferencePoseGenerator {
    private let confidenceThreshold = 0.3
    private let lengthTolerance: CGFloat = 0.001

    public init() {}

    public func generateReference(for pose: BodyPose, view: PostureView, profile: PostureReferenceProfile) -> ReferenceGenerationResult {
        guard view != .uncertain else { return unavailable("Choose a front or side view to display an alignment reference.") }
        guard pose.imageWidth > 0, pose.imageHeight > 0 else { return unavailable("The image dimensions are unavailable for alignment reference.") }

        let observed = validPoints(in: pose)
        guard !observed.isEmpty else { return unavailable("No reliable body landmarks were detected for alignment reference.") }
        let regions = supportedRegions(in: observed, view: view)
        guard !regions.isEmpty else { return unavailable("Insufficient reliable landmarks to generate alignment reference.") }
        let rules = Dictionary(profile.rules(for: view).map { ($0.measurementID, $0) }, uniquingKeysWith: { _, latest in latest })
        guard !rules.isEmpty else { return unavailable("This profile has no alignment rules for the selected view.") }

        func solve(_ fraction: CGFloat) -> [LandmarkType: CGPoint]? {
            solvePose(observed: observed, regions: regions, view: view, rules: rules, imageWidth: pose.imageWidth, fraction: fraction)
        }

        // Rules are soft objectives. Find the strongest correction that remains
        // feasible rather than throwing away the whole reference.
        var feasibleFraction: CGFloat = 1
        var finalPoints = solve(1)
        if finalPoints == nil || !validLengths(original: observed, solved: finalPoints!, view: view) {
            var low: CGFloat = 0
            var high: CGFloat = 1
            for _ in 0..<24 {
                let candidate = (low + high) / 2
                if let points = solve(candidate), validLengths(original: observed, solved: points, view: view) {
                    low = candidate
                } else {
                    high = candidate
                }
            }
            feasibleFraction = low
            finalPoints = solve(low)
        }
        guard let finalPoints else { return unavailable("The available landmarks could not produce stable reference geometry.") }

        let partialReason = partialReason(regions: regions)
        let captions = achievedChanges(original: observed, solved: finalPoints, view: view, rules: rules, regions: regions)
        let staticReference = makeReference(points: finalPoints, regions: regions, view: view, captions: captions, reason: partialReason)
        guard feasibleFraction > 0.001, moved(from: observed, to: finalPoints) else {
            let reason = partialReason ?? "The measured pose is already within this profile's reference targets."
            return ReferenceGenerationResult(staticReference: staticReference, isReplayAvailable: false, unavailabilityReason: reason)
        }

        // Start with the measured pose so replay never jumps to a partly-corrected frame.
        var sequence: [ReferencePose] = []
        let frameCount = 31
        for index in 0..<frameCount {
            let fraction = feasibleFraction * CGFloat(index) / CGFloat(frameCount - 1)
            guard let frame = solve(fraction), validLengths(original: observed, solved: frame, view: view) else {
                return ReferenceGenerationResult(staticReference: staticReference, isReplayAvailable: false, unavailabilityReason: "Replay is unavailable because an intermediate pose was unstable.")
            }
            sequence.append(makeReference(points: frame, regions: regions, view: view, captions: [], reason: partialReason))
        }
        return ReferenceGenerationResult(staticReference: staticReference, motionSequence: sequence, isReplayAvailable: true, unavailabilityReason: partialReason)
    }

    private func unavailable(_ reason: String) -> ReferenceGenerationResult {
        let reference = ReferencePose(unavailabilityReason: reason)
        return ReferenceGenerationResult(staticReference: reference, isReplayAvailable: false, unavailabilityReason: reason)
    }

    private func validPoints(in pose: BodyPose) -> [LandmarkType: CGPoint] {
        pose.landmarks.reduce(into: [:]) { output, item in
            if item.value.confidence >= confidenceThreshold || item.value.isManuallyCorrected { output[item.key] = item.value.imageLocation }
        }
    }

    private func supportedRegions(in points: [LandmarkType: CGPoint], view: PostureView) -> Set<BodyRegion> {
        var regions: Set<BodyRegion> = []
        switch view {
        case .front:
            if has(points, .leftHip, .rightHip), (has(points, .leftKnee, .leftAnkle) || has(points, .rightKnee, .rightAnkle)) { regions.insert(.legs) }
            if has(points, .leftShoulder, .rightShoulder, .leftHip, .rightHip) { regions.insert(.torso) }
            if points[.neck] != nil, [.nose, .leftEye, .rightEye, .leftEar, .rightEar].contains(where: { points[$0] != nil }) { regions.insert(.head) }
            if points[.leftShoulder] != nil || points[.rightShoulder] != nil { regions.insert(.arms) }
        case .leftSide, .rightSide:
            let keys = sideKeys(view)
            if has(points, keys.hip, keys.knee, keys.ankle) { regions.insert(.legs) }
            if has(points, keys.hip, keys.shoulder) { regions.insert(.torso) }
            if (points[keys.ear] != nil || points[.nose] != nil), (points[keys.shoulder] != nil || points[.neck] != nil) { regions.insert(.head) }
            if points[keys.shoulder] != nil { regions.insert(.arms) }
        case .uncertain:
            break
        }
        return regions
    }

    private func has(_ points: [LandmarkType: CGPoint], _ types: LandmarkType...) -> Bool { types.allSatisfy { points[$0] != nil } }

    private struct SideKeys {
        let ankle: LandmarkType, knee: LandmarkType, hip: LandmarkType, shoulder: LandmarkType
        let ear: LandmarkType, elbow: LandmarkType, wrist: LandmarkType
    }

    private func sideKeys(_ view: PostureView) -> SideKeys {
        view == .rightSide
            ? SideKeys(ankle: .rightAnkle, knee: .rightKnee, hip: .rightHip, shoulder: .rightShoulder, ear: .rightEar, elbow: .rightElbow, wrist: .rightWrist)
            : SideKeys(ankle: .leftAnkle, knee: .leftKnee, hip: .leftHip, shoulder: .leftShoulder, ear: .leftEar, elbow: .leftElbow, wrist: .leftWrist)
    }

    private func solvePose(observed: [LandmarkType: CGPoint], regions: Set<BodyRegion>, view: PostureView, rules: [MeasurementID: TargetAlignmentRule], imageWidth: CGFloat, fraction: CGFloat) -> [LandmarkType: CGPoint]? {
        var solved = observed
        let succeeded: Bool
        switch view {
        case .front:
            succeeded = solveFront(&solved, observed: observed, regions: regions, rules: rules, imageWidth: imageWidth, fraction: fraction)
        case .leftSide, .rightSide:
            succeeded = solveSide(&solved, observed: observed, regions: regions, rules: rules, view: view, imageWidth: imageWidth, fraction: fraction)
        case .uncertain:
            return nil
        }
        return succeeded && solved.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) ? solved : nil
    }

    private func solveFront(_ solved: inout [LandmarkType: CGPoint], observed: [LandmarkType: CGPoint], regions: Set<BodyRegion>, rules: [MeasurementID: TargetAlignmentRule], imageWidth: CGFloat, fraction: CGFloat) -> Bool {
        let ankles = midpoint(observed[.leftAnkle], observed[.rightAnkle])
        let oldHips = midpoint(observed[.leftHip], observed[.rightHip])
        let oldShoulders = midpoint(observed[.leftShoulder], observed[.rightShoulder])

        if regions.contains(.torso), let lh = observed[.leftHip], let rh = observed[.rightHip], let ls = observed[.leftShoulder], let rs = observed[.rightShoulder], let hipCenterObserved = oldHips, let shoulderCenterObserved = oldShoulders {
            var hipCenter = hipCenterObserved
            var shoulderCenter = shoulderCenterObserved
            if let ankles, let rule = rules[.bodyCenterlineDeviation] {
                hipCenter.x = lerp(hipCenter.x, ankles.x + CGFloat(rule.targetValue) * imageWidth / 100, fraction)
            }
            let hipAngle = targetLineDegrees(rule: rules[.hipLineAngle], first: lh, second: rh)
            solved[.leftHip] = rotatePair(lh, other: rh, newCenter: hipCenter, targetDegrees: hipAngle, fraction: fraction)
            solved[.rightHip] = rotatePair(rh, other: lh, newCenter: hipCenter, targetDegrees: hipAngle, fraction: fraction)

            if let rule = rules[.torsoLateralDeviation], let newHips = midpoint(solved[.leftHip], solved[.rightHip]) {
                let vertical = abs(shoulderCenter.y - newHips.y)
                let targetX = newHips.x + tan(CGFloat(rule.targetValue) * .pi / 180) * vertical
                shoulderCenter.x = lerp(shoulderCenter.x, targetX, fraction)
            } else if let ankles, let rule = rules[.bodyCenterlineDeviation] {
                shoulderCenter.x = lerp(shoulderCenter.x, ankles.x + CGFloat(rule.targetValue) * imageWidth / 100, fraction)
            }
            let shoulderAngle = targetLineDegrees(rule: rules[.shoulderLineAngle], first: ls, second: rs)
            let desiredLeft = rotatePair(ls, other: rs, newCenter: shoulderCenter, targetDegrees: shoulderAngle, fraction: fraction)
            let desiredRight = rotatePair(rs, other: ls, newCenter: shoulderCenter, targetDegrees: shoulderAngle, fraction: fraction)
            guard let newLeftHip = solved[.leftHip], let newRightHip = solved[.rightHip],
                  let shoulders = constrainedShoulders(
                    leftHip: newLeftHip,
                    rightHip: newRightHip,
                    leftTorsoLength: distance(lh, ls),
                    rightTorsoLength: distance(rh, rs),
                    shoulderWidth: distance(ls, rs),
                    desiredLeft: desiredLeft,
                    desiredRight: desiredRight,
                    observedLeft: ls,
                    observedRight: rs,
                    fraction: fraction
                  ) else { return false }
            solved[.leftShoulder] = shoulders.0
            solved[.rightShoulder] = shoulders.1
            shoulderCenter = (shoulders.0 + shoulders.1) / 2
            shift(.neck, solved: &solved, observed: observed, offset: shoulderCenter - shoulderCenterObserved)
            shift(.root, solved: &solved, observed: observed, offset: hipCenter - hipCenterObserved)
        }

        if regions.contains(.legs) {
            let ankleCenter = midpoint(observed[.leftAnkle], observed[.rightAnkle])
            let ankleWidth = observed[.leftAnkle].flatMap { left in observed[.rightAnkle].map { distance(left, $0) } }
            for (hipKey, kneeKey, ankleKey) in [(LandmarkType.leftHip, LandmarkType.leftKnee, LandmarkType.leftAnkle), (.rightHip, .rightKnee, .rightAnkle)] {
                guard let hip = solved[hipKey], let oldHip = observed[hipKey], let oldKnee = observed[kneeKey], let ankle = observed[ankleKey] else { continue }
                let thigh = distance(oldHip, oldKnee), shin = distance(oldKnee, ankle)
                var target = hip + (ankle - hip) * (thigh / max(thigh + shin, 0.001))
                if let rule = rules[.kneeAnkleStanceRatio], let ankleCenter, let ankleWidth {
                    let sideSign: CGFloat = ankle.x < ankleCenter.x ? -1 : 1
                    target.x = ankleCenter.x + sideSign * ankleWidth * CGFloat(rule.targetValue) / 2
                }
                let desired = rules[.kneeAnkleStanceRatio] != nil ? lerp(oldKnee, target, fraction) : oldKnee
                guard let knee = circlePoint(center1: hip, radius1: thigh, center2: ankle, radius2: shin, desired: desired) else { return false }
                solved[kneeKey] = knee
            }
        }

        if regions.contains(.head), let oldOrigin = observed[.neck], let newOrigin = solved[.neck] {
            let headTypes: [LandmarkType] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
            let center = headCenter(observed) ?? oldOrigin
            var angle: CGFloat = 0
            if let rule = rules[.headTiltAngle], let pair = firstPair(observed, [(.leftEye, .rightEye), (.leftEar, .rightEar)]) {
                let delta = shortestRotation(from: lineRadians(pair.0, pair.1), to: CGFloat(rule.targetValue) * .pi / 180)
                if abs(delta * 180 / .pi) > CGFloat(rule.tolerance) { angle = delta * fraction }
            }
            var translation = newOrigin - oldOrigin
            if let ankles, let rule = rules[.bodyCenterlineDeviation] {
                let targetX = ankles.x + CGFloat(rule.targetValue) * imageWidth / 100
                translation.x += (targetX - (center.x + translation.x)) * fraction
            }
            for type in headTypes { if let point = observed[type] { solved[type] = rotate(point, center: center, angle: angle) + translation } }
        }
        translateArms(solved: &solved, observed: observed)
        return true
    }

    private func solveSide(_ solved: inout [LandmarkType: CGPoint], observed: [LandmarkType: CGPoint], regions: Set<BodyRegion>, rules: [MeasurementID: TargetAlignmentRule], view: PostureView, imageWidth: CGFloat, fraction: CGFloat) -> Bool {
        let keys = sideKeys(view)
        let ankle = observed[keys.ankle]
        let anchorX = ankle?.x ?? observed[keys.hip]?.x ?? observed[keys.shoulder]?.x

        if regions.contains(.legs), let ankle, let oldHip = observed[keys.hip], let oldKnee = observed[keys.knee] {
            let thigh = distance(oldHip, oldKnee), shin = distance(oldKnee, ankle)
            let oldDirect = distance(oldHip, ankle)
            var direct = oldDirect
            if let rule = rules[.kneeJointAngle] {
                let currentAngle = vertexDegrees(first: oldHip, vertex: oldKnee, third: ankle)
                if abs(currentAngle - CGFloat(rule.targetValue)) > CGFloat(rule.tolerance) {
                    let angle = lerp(currentAngle, CGFloat(rule.targetValue), fraction) * .pi / 180
                    direct = sqrt(max(0, thigh * thigh + shin * shin - 2 * thigh * shin * cos(angle)))
                }
            }
            var hip = oldHip
            if rules[.hipKneeAlignmentAngle] != nil || rules[.kneeJointAngle] != nil || rules[.overallSagittalBodyLean] != nil {
                let targetAngle = CGFloat(rules[.overallSagittalBodyLean]?.targetValue ?? 0) * .pi / 180
                hip.x = lerp(hip.x, ankle.x + sin(targetAngle) * direct, fraction)
                let dx = hip.x - ankle.x
                guard abs(dx) <= direct else { return false }
                hip.y = ankle.y - sqrt(max(0, direct * direct - dx * dx))
            }
            solved[keys.hip] = hip
            var targetKnee = hip + (ankle - hip) * (thigh / max(thigh + shin, 0.001))
            if let rule = rules[.hipKneeAlignmentAngle] {
                let angle = CGFloat(rule.targetValue) * .pi / 180
                targetKnee = CGPoint(x: hip.x + sin(angle) * thigh, y: hip.y + cos(angle) * thigh)
            }
            let wantsKneeChange = rules[.hipKneeAlignmentAngle] != nil || rules[.kneeJointAngle] != nil
            guard let knee = circlePoint(center1: hip, radius1: thigh, center2: ankle, radius2: shin, desired: wantsKneeChange ? lerp(oldKnee, targetKnee, fraction) : oldKnee) else { return false }
            solved[keys.knee] = knee
        }

        if regions.contains(.torso), let hip = solved[keys.hip], let oldHip = observed[keys.hip], let oldShoulder = observed[keys.shoulder] {
            let length = distance(oldHip, oldShoulder)
            var targetX = oldShoulder.x
            if let rule = rules[.torsoInclinationAngle] {
                let currentAngle = atan2(oldShoulder.x - oldHip.x, oldHip.y - oldShoulder.y) * 180 / .pi
                if abs(currentAngle - CGFloat(rule.targetValue)) > CGFloat(rule.tolerance) {
                    targetX = hip.x + sin(CGFloat(rule.targetValue) * .pi / 180) * length
                }
            }
            else if let rule = rules[.overallSagittalBodyLean], let anchorX {
                let topToAnchor = observed[keys.ankle].map { distance(oldShoulder, $0) } ?? length
                targetX = anchorX + sin(CGFloat(rule.targetValue) * .pi / 180) * topToAnchor
            }
            let x = lerp(oldShoulder.x, targetX, fraction), dx = x - hip.x
            guard abs(dx) <= length else { return false }
            let shoulder = CGPoint(x: x, y: hip.y - sqrt(max(0, length * length - dx * dx)))
            solved[keys.shoulder] = shoulder
            shift(.neck, solved: &solved, observed: observed, offset: shoulder - oldShoulder)
        }

        if regions.contains(.head), let oldBase = observed[keys.shoulder] ?? observed[.neck], let newBase = solved[keys.shoulder] ?? solved[.neck] {
            var translation = newBase - oldBase
            if let anchor = observed[keys.ear] ?? observed[.nose], let rule = rules[.earShoulderHorizontalOffset] {
                let currentOffset = (anchor.x - oldBase.x) / imageWidth * 100
                if abs(currentOffset - CGFloat(rule.targetValue)) > CGFloat(rule.tolerance) {
                    let targetX = newBase.x + CGFloat(rule.targetValue) * imageWidth / 100
                    translation.x += (targetX - (anchor.x + translation.x)) * fraction
                }
            }
            for type in [LandmarkType.nose, .leftEye, .rightEye, .leftEar, .rightEar] { if let point = observed[type] { solved[type] = point + translation } }
        }
        translateArms(solved: &solved, observed: observed, side: keys)
        return true
    }

    private func rotatePair(_ point: CGPoint, other: CGPoint, newCenter: CGPoint, targetDegrees: CGFloat, fraction: CGFloat) -> CGPoint {
        let center = (point + other) / 2
        let rotation = shortestRotation(from: lineRadians(point, other), to: targetDegrees * .pi / 180) * fraction
        return rotate(point, center: center, angle: rotation) + (newCenter - center)
    }

    private func shortestRotation(from: CGFloat, to: CGFloat) -> CGFloat {
        var delta = to - from
        while delta > .pi / 2 { delta -= .pi }
        while delta < -.pi / 2 { delta += .pi }
        return delta
    }

    private func targetLineDegrees(rule: TargetAlignmentRule?, first: CGPoint, second: CGPoint) -> CGFloat {
        let current = lineRadians(first, second)
        guard let rule else { return current * 180 / .pi }
        let target = CGFloat(rule.targetValue) * .pi / 180
        let error = shortestRotation(from: current, to: target)
        return abs(error * 180 / .pi) <= CGFloat(rule.tolerance) ? current * 180 / .pi : CGFloat(rule.targetValue)
    }

    private func circlePoint(center1: CGPoint, radius1: CGFloat, center2: CGPoint, radius2: CGFloat, desired: CGPoint) -> CGPoint? {
        let delta = center2 - center1, d = hypot(delta.x, delta.y)
        guard d > 0.001, d <= radius1 + radius2 + 0.001, d >= abs(radius1 - radius2) - 0.001 else { return nil }
        let a = (radius1 * radius1 - radius2 * radius2 + d * d) / (2 * d)
        let h = sqrt(max(0, radius1 * radius1 - a * a)), unit = delta / d
        let base = center1 + unit * a, perpendicular = CGPoint(x: -unit.y, y: unit.x) * h
        let first = base + perpendicular, second = base - perpendicular
        return distance(first, desired) <= distance(second, desired) ? first : second
    }

    /// Solves the four-bar torso linkage and selects the feasible arrangement
    /// closest to the profile's desired shoulder line.
    private func constrainedShoulders(
        leftHip: CGPoint,
        rightHip: CGPoint,
        leftTorsoLength: CGFloat,
        rightTorsoLength: CGFloat,
        shoulderWidth: CGFloat,
        desiredLeft: CGPoint,
        desiredRight: CGPoint,
        observedLeft: CGPoint,
        observedRight: CGPoint,
        fraction: CGFloat
    ) -> (CGPoint, CGPoint)? {
        if fraction == 0 { return (observedLeft, observedRight) }
        var best: (CGPoint, CGPoint)?
        var bestScore = CGFloat.greatestFiniteMagnitude
        if abs(distance(leftHip, observedLeft) - leftTorsoLength) < 0.001,
           abs(distance(rightHip, observedRight) - rightTorsoLength) < 0.001 {
            best = (observedLeft, observedRight)
            bestScore = squaredDistance(observedLeft, desiredLeft) + squaredDistance(observedRight, desiredRight)
        }
        let samples = 1440
        for index in 0..<samples {
            let angle = CGFloat(index) * 2 * .pi / CGFloat(samples)
            let left = CGPoint(
                x: leftHip.x + cos(angle) * leftTorsoLength,
                y: leftHip.y + sin(angle) * leftTorsoLength
            )
            for right in circlePoints(center1: left, radius1: shoulderWidth, center2: rightHip, radius2: rightTorsoLength) {
                let score = squaredDistance(left, desiredLeft) + squaredDistance(right, desiredRight)
                if score < bestScore {
                    bestScore = score
                    best = (left, right)
                }
            }
        }
        return best
    }

    private func circlePoints(center1: CGPoint, radius1: CGFloat, center2: CGPoint, radius2: CGFloat) -> [CGPoint] {
        let delta = center2 - center1, d = hypot(delta.x, delta.y)
        guard d > 0.001, d <= radius1 + radius2 + 0.001, d >= abs(radius1 - radius2) - 0.001 else { return [] }
        let a = (radius1 * radius1 - radius2 * radius2 + d * d) / (2 * d)
        let h = sqrt(max(0, radius1 * radius1 - a * a)), unit = delta / d
        let base = center1 + unit * a, perpendicular = CGPoint(x: -unit.y, y: unit.x) * h
        return h < 0.001 ? [base] : [base + perpendicular, base - perpendicular]
    }

    private func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let delta = second - first
        return delta.x * delta.x + delta.y * delta.y
    }

    private func validLengths(original: [LandmarkType: CGPoint], solved: [LandmarkType: CGPoint], view: PostureView) -> Bool {
        let pairs: [(LandmarkType, LandmarkType)]
        switch view {
        case .front:
            pairs = [(.leftShoulder, .rightShoulder), (.leftHip, .rightHip), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist)]
        case .leftSide, .rightSide:
            let keys = sideKeys(view)
            pairs = [(keys.shoulder, keys.hip), (keys.hip, keys.knee), (keys.knee, keys.ankle), (keys.shoulder, keys.elbow), (keys.elbow, keys.wrist)]
        case .uncertain:
            return false
        }
        return pairs.allSatisfy { pair in
            guard let oldA = original[pair.0], let oldB = original[pair.1], let newA = solved[pair.0], let newB = solved[pair.1] else { return true }
            let oldLength = distance(oldA, oldB)
            return oldLength < 0.001 || abs(distance(newA, newB) - oldLength) / oldLength <= lengthTolerance
        }
    }

    private func achievedChanges(original: [LandmarkType: CGPoint], solved: [LandmarkType: CGPoint], view: PostureView, rules: [MeasurementID: TargetAlignmentRule], regions: Set<BodyRegion>) -> [String] {
        var output: [String] = []
        switch view {
        case .front:
            if let rule = rules[.shoulderLineAngle], reducedLineError(.leftShoulder, .rightShoulder, original, solved, rule.targetValue) { output.append("Shoulder reference: moved toward the profile angle.") }
            if let rule = rules[.hipLineAngle], reducedLineError(.leftHip, .rightHip, original, solved, rule.targetValue) { output.append("Hip reference: moved toward the profile angle.") }
            if regions.contains(.head), moved([.nose, .leftEye, .rightEye, .leftEar, .rightEar], from: original, to: solved) { output.append("Head reference: moved toward the configured alignment.") }
            if regions.contains(.torso), moved([.leftShoulder, .rightShoulder, .leftHip, .rightHip], from: original, to: solved) { output.append("Torso reference: moved toward the configured alignment.") }
            if regions.contains(.legs), moved([.leftKnee, .rightKnee], from: original, to: solved) { output.append("Knee reference: moved toward the hip-to-ankle lines.") }
        case .leftSide, .rightSide:
            let keys = sideKeys(view)
            if regions.contains(.head), moved([.nose, .leftEye, .rightEye, .leftEar, .rightEar], from: original, to: solved) { output.append("Head reference: moved toward the configured ear-to-shoulder offset.") }
            if regions.contains(.torso), moved([keys.shoulder, keys.hip], from: original, to: solved) { output.append("Torso reference: moved toward the configured side alignment.") }
            if regions.contains(.legs), moved([keys.hip, keys.knee], from: original, to: solved) { output.append("Leg reference: moved toward the configured side alignment.") }
        case .uncertain:
            break
        }
        return output
    }

    private func reducedLineError(_ first: LandmarkType, _ second: LandmarkType, _ original: [LandmarkType: CGPoint], _ solved: [LandmarkType: CGPoint], _ target: Double) -> Bool {
        guard let oldA = original[first], let oldB = original[second], let newA = solved[first], let newB = solved[second] else { return false }
        let desired = CGFloat(target) * .pi / 180
        return abs(shortestRotation(from: lineRadians(oldA, oldB), to: desired)) - abs(shortestRotation(from: lineRadians(newA, newB), to: desired)) > 0.0001
    }

    private func makeReference(points: [LandmarkType: CGPoint], regions: Set<BodyRegion>, view: PostureView, captions: [String], reason: String?) -> ReferencePose {
        let types = includedTypes(regions, view)
        let filtered = points.filter { types.contains($0.key) }
        let candidates: [(LandmarkType, LandmarkType)]
        switch view {
        case .front: candidates = BodyPose.connections
        case .leftSide, .rightSide:
            let keys = sideKeys(view)
            candidates = [(keys.ear, keys.shoulder), (keys.shoulder, keys.hip), (keys.hip, keys.knee), (keys.knee, keys.ankle), (keys.shoulder, keys.elbow), (keys.elbow, keys.wrist)]
        case .uncertain: candidates = []
        }
        let connections = candidates.compactMap { filtered[$0.0] != nil && filtered[$0.1] != nil ? ConnectionPair($0.0, $0.1) : nil }
        return ReferencePose(jointLocations: filtered, connections: connections, supportedRegions: regions, achievedChanges: captions, unavailabilityReason: reason)
    }

    private func includedTypes(_ regions: Set<BodyRegion>, _ view: PostureView) -> Set<LandmarkType> {
        var types: Set<LandmarkType> = []
        let keys = sideKeys(view)
        if regions.contains(.head) { types.formUnion([.nose, .neck, .leftEye, .rightEye, .leftEar, .rightEar]) }
        if regions.contains(.torso) { types.formUnion(view == .front ? [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .neck, .root] : [keys.shoulder, keys.hip, .neck]) }
        if regions.contains(.legs) { types.formUnion(view == .front ? [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle] : [keys.hip, keys.knee, keys.ankle]) }
        if regions.contains(.arms) { types.formUnion(view == .front ? [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist] : [keys.shoulder, keys.elbow, keys.wrist]) }
        return types
    }

    private func partialReason(regions: Set<BodyRegion>) -> String? {
        let missing = Set([BodyRegion.head, .torso, .legs]).subtracting(regions)
        return missing.isEmpty ? nil : "Partial guidance: reliable anchors were unavailable for \(missing.map(\.rawValue).sorted().joined(separator: ", "))."
    }

    private func translateArms(solved: inout [LandmarkType: CGPoint], observed: [LandmarkType: CGPoint], side: SideKeys? = nil) {
        let arms: [(LandmarkType, LandmarkType, LandmarkType)] = side.map { [($0.shoulder, $0.elbow, $0.wrist)] } ?? [(.leftShoulder, .leftElbow, .leftWrist), (.rightShoulder, .rightElbow, .rightWrist)]
        for (shoulder, elbow, wrist) in arms where observed[shoulder] != nil && solved[shoulder] != nil {
            let offset = solved[shoulder]! - observed[shoulder]!
            shift(elbow, solved: &solved, observed: observed, offset: offset)
            shift(wrist, solved: &solved, observed: observed, offset: offset)
        }
    }

    private func shift(_ type: LandmarkType, solved: inout [LandmarkType: CGPoint], observed: [LandmarkType: CGPoint], offset: CGPoint?) {
        if let point = observed[type], let offset { solved[type] = point + offset }
    }

    private func firstPair(_ points: [LandmarkType: CGPoint], _ candidates: [(LandmarkType, LandmarkType)]) -> (CGPoint, CGPoint)? {
        for pair in candidates { if let first = points[pair.0], let second = points[pair.1] { return (first, second) } }
        return nil
    }

    private func headCenter(_ points: [LandmarkType: CGPoint]) -> CGPoint? { points[.nose] ?? midpoint(points[.leftEye], points[.rightEye]) ?? midpoint(points[.leftEar], points[.rightEar]) }
    private func midpoint(_ first: CGPoint?, _ second: CGPoint?) -> CGPoint? { first.flatMap { a in second.map { (a + $0) / 2 } } }
    private func lineRadians(_ first: CGPoint, _ second: CGPoint) -> CGFloat { atan2(second.y - first.y, second.x - first.x) }
    private func lineDegrees(_ first: CGPoint, _ second: CGPoint) -> Double { Double(lineRadians(first, second) * 180 / .pi) }
    private func vertexDegrees(first: CGPoint, vertex: CGPoint, third: CGPoint) -> CGFloat {
        let firstVector = first - vertex, secondVector = third - vertex
        let denominator = max(distance(first, vertex) * distance(third, vertex), 0.001)
        let cosine = max(-1, min(1, (firstVector.x * secondVector.x + firstVector.y * secondVector.y) / denominator))
        return acos(cosine) * 180 / .pi
    }
    private func rotate(_ point: CGPoint, center: CGPoint, angle: CGFloat) -> CGPoint {
        let p = point - center, c = cos(angle), s = sin(angle)
        return CGPoint(x: center.x + p.x * c - p.y * s, y: center.y + p.x * s + p.y * c)
    }
    private func lerp(_ start: CGFloat, _ end: CGFloat, _ fraction: CGFloat) -> CGFloat { start + (end - start) * fraction }
    private func lerp(_ start: CGPoint, _ end: CGPoint, _ fraction: CGFloat) -> CGPoint { start + (end - start) * fraction }
    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat { hypot(second.x - first.x, second.y - first.y) }
    private func moved(from original: [LandmarkType: CGPoint], to solved: [LandmarkType: CGPoint]) -> Bool { moved(Array(original.keys), from: original, to: solved) }
    private func moved(_ types: [LandmarkType], from original: [LandmarkType: CGPoint], to solved: [LandmarkType: CGPoint]) -> Bool {
        types.contains { type in original[type].flatMap { old in solved[type].map { distance(old, $0) > 0.5 } } ?? false }
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }
    static func / (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x / rhs, y: lhs.y / rhs) }
}
