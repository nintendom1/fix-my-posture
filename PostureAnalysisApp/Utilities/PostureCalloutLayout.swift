import CoreGraphics
import Foundation

public enum PostureCalloutRegion: String, CaseIterable, Hashable {
    case head
    case shoulders
    case torso
    case hips
    case legs
    case wholeBody
}

public struct PostureCalloutItem: Identifiable, Equatable {
    public let measurement: PostureMeasurement
    public let feedback: MeasurementFeedback
    public let region: PostureCalloutRegion
    public let anchor: CGPoint

    public var id: String { measurement.id }
}

public struct PostureCalloutPlacement: Identifiable, Equatable {
    public let item: PostureCalloutItem
    public let frame: CGRect

    public var id: String { item.id }
}

/// Pure geometry used by live and still-image overlays.
public enum PostureCalloutLayout {
    public static func items(
        measurements: [PostureMeasurement],
        pose: BodyPose,
        containerSize: CGSize,
        view: PostureView,
        profile: PostureReferenceProfile
    ) -> [PostureCalloutItem] {
        let evaluator = MeasurementFeedbackEvaluator()
        let eligible = measurements.compactMap { measurement -> PostureCalloutItem? in
            let feedback = evaluator.feedback(for: measurement, view: view, profile: profile)
            guard !feedback.isLowConfidence, feedback.severity != .unavailable,
                  let region = region(for: measurement.measurementID),
                  let anchor = anchor(for: region, measurement: measurement, pose: pose, containerSize: containerSize)
            else { return nil }
            return PostureCalloutItem(measurement: measurement, feedback: feedback, region: region, anchor: anchor)
        }

        let ranked = eligible.sorted { lhs, rhs in
            if lhs.feedback.severity != rhs.feedback.severity { return lhs.feedback.severity > rhs.feedback.severity }
            if lhs.feedback.normalizedDeviation != rhs.feedback.normalizedDeviation {
                return (lhs.feedback.normalizedDeviation ?? -1) > (rhs.feedback.normalizedDeviation ?? -1)
            }
            return lhs.measurement.id < rhs.measurement.id
        }

        var used = Set<PostureCalloutRegion>()
        return ranked.filter { used.insert($0.region).inserted }
    }

    public static func placements(
        items: [PostureCalloutItem],
        pose: BodyPose,
        containerSize: CGSize,
        reservedRects: [CGRect] = [],
        widths: [CGFloat] = [120, 104, 88],
        cardHeight: CGFloat = 76,
        targetRects: [CGRect] = [],
        previous: [PostureCalloutPlacement] = [],
        contentHeight: ((PostureCalloutItem, CGFloat) -> CGFloat)? = nil
    ) -> [PostureCalloutPlacement] {
        guard containerSize.width > 0, containerSize.height > 0 else { return [] }
        let safeBounds = CGRect(origin: .zero, size: containerSize).insetBy(dx: 8, dy: 8)
        let bodyRects = protectedBodyRects(pose: pose, containerSize: containerSize).map { $0.insetBy(dx: -8, dy: -8) } + targetRects.map { $0.insetBy(dx: -8, dy: -8) }
        let verticalOffsets: [CGFloat] = [0, -24, 24, -48, 48, -72, 72]
        var occupied = reservedRects.map { $0.insetBy(dx: -8, dy: -8) }
        var result: [PostureCalloutPlacement] = []

        for item in items {
            let anchor = CGPoint(x: quantize(item.anchor.x), y: quantize(item.anchor.y))
            let preferredDirections: [CGFloat] = anchor.x < containerSize.width / 2 ? [-1, 1] : [1, -1]
            var selected: CGRect?

            func fits(_ frame: CGRect) -> Bool {
                safeBounds.contains(frame) && !occupied.contains(where: { $0.intersects(frame) }) && !bodyRects.contains(where: { $0.intersects(frame) })
            }
            if let old = previous.first(where: { $0.id == item.id }), widths.contains(old.frame.width),
               abs(old.item.anchor.y - anchor.y) < 32 {
                let height = contentHeight?(item, old.frame.width) ?? cardHeight
                let frame = CGRect(x: old.frame.minX, y: old.frame.minY, width: old.frame.width, height: height)
                if height.isFinite, height > 0, fits(frame) { selected = frame }
            }
            search: for width in widths where selected == nil {
                let height = contentHeight?(item, width) ?? cardHeight
                guard height.isFinite, height > 0 else { continue }
                for direction in preferredDirections {
                    for yOffset in verticalOffsets {
                        let centerY = anchor.y + yOffset
                        let local = bodyRects.filter { $0.maxY > centerY - height / 2 && $0.minY < centerY + height / 2 }
                        let boundary = direction < 0 ? min(anchor.x, local.map(\.minX).min() ?? anchor.x) : max(anchor.x, local.map(\.maxX).max() ?? anchor.x)
                        let frame = CGRect(x: direction < 0 ? boundary - width : boundary,
                                           y: centerY - height / 2, width: width, height: height)
                        guard fits(frame) else { continue }
                        selected = frame
                        break search
                    }
                }
            }

            if let frame = selected {
                result.append(PostureCalloutPlacement(item: PostureCalloutItem(
                    measurement: item.measurement,
                    feedback: item.feedback,
                    region: item.region,
                    anchor: anchor
                ), frame: frame))
                occupied.append(frame.insetBy(dx: -8, dy: -8))
            }
        }
        return result
    }

    public static func shortName(for measurementID: MeasurementID) -> String {
        switch measurementID {
        case .headTiltAngle: return "Head tilt"
        case .forwardHeadAngle: return "Forward head"
        case .earShoulderHorizontalOffset: return "Head offset"
        case .shoulderLineAngle: return "Shoulders"
        case .shoulderHeightAsymmetry: return "Shoulder height"
        case .torsoLateralDeviation: return "Torso lean"
        case .torsoInclinationAngle: return "Torso angle"
        case .hipLineAngle: return "Hips"
        case .hipHeightAsymmetry: return "Hip height"
        case .hipKneeAlignmentAngle: return "Hip–knee"
        case .kneeJointAngle: return "Knee angle"
        case .kneeAnkleStanceRatio: return "Stance"
        case .bodyCenterlineDeviation: return "Centerline"
        case .overallSagittalBodyLean: return "Body lean"
        case .custom: return "Measurement"
        }
    }

    private static func region(for id: MeasurementID) -> PostureCalloutRegion? {
        switch id {
        case .headTiltAngle, .forwardHeadAngle, .earShoulderHorizontalOffset: return .head
        case .shoulderLineAngle, .shoulderHeightAsymmetry: return .shoulders
        case .torsoLateralDeviation, .torsoInclinationAngle: return .torso
        case .hipLineAngle, .hipHeightAsymmetry, .hipKneeAlignmentAngle: return .hips
        case .kneeJointAngle, .kneeAnkleStanceRatio: return .legs
        case .bodyCenterlineDeviation, .overallSagittalBodyLean: return .wholeBody
        case .custom: return nil
        }
    }

    private static func anchor(
        for region: PostureCalloutRegion,
        measurement: PostureMeasurement,
        pose: BodyPose,
        containerSize: CGSize
    ) -> CGPoint? {
        let preferred: [LandmarkType]
        switch region {
        case .head: preferred = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
        case .shoulders: preferred = [.leftShoulder, .rightShoulder]
        case .torso: preferred = [.neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .root]
        case .hips: preferred = [.leftHip, .rightHip, .root]
        case .legs: preferred = measurement.landmarksUsed.filter { [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle].contains($0) }
        case .wholeBody: preferred = [.neck, .root, .leftHip, .rightHip]
        }
        let points = preferred.compactMap { pose[$0]?.normalizedLocation }
        guard !points.isEmpty else { return nil }
        let average = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                              y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        return CoordinateConverter.normalizedToContainer(
            normalized: average,
            imageSize: CGSize(width: pose.imageWidth, height: pose.imageHeight),
            containerSize: containerSize
        )
    }

    private static func protectedBodyRects(pose: BodyPose, containerSize: CGSize) -> [CGRect] {
        let imageSize = CGSize(width: pose.imageWidth, height: pose.imageHeight)
        func point(_ type: LandmarkType) -> CGPoint? {
            pose[type].map { CoordinateConverter.normalizedToContainer(
                normalized: $0.normalizedLocation, imageSize: imageSize, containerSize: containerSize) }
        }
        var rects = pose.landmarks.keys.compactMap { type -> CGRect? in
            guard let p = point(type) else { return nil }
            let radius: CGFloat = [.nose, .leftEye, .rightEye, .leftEar, .rightEar].contains(type) ? 24 : 14
            return CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        }
        for (a, b) in BodyPose.connections {
            guard let p1 = point(a), let p2 = point(b) else { continue }
            // Sampling follows the segment closely; an axis-aligned bounding box would
            // incorrectly reserve the empty corners around diagonal arms and legs.
            // Overlapping samples every <= 4 pt continuously cover the segment,
            // including diagonal gaps between the old three samples.
            let steps = max(1, Int(ceil(hypot(p2.x - p1.x, p2.y - p1.y) / 4)))
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let sample = CGPoint(x: p1.x + (p2.x - p1.x) * progress,
                                     y: p1.y + (p2.y - p1.y) * progress)
                rects.append(CGRect(x: sample.x - 10, y: sample.y - 10, width: 20, height: 20))
            }
        }
        let torsoTypes: [LandmarkType] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .root]
        let torsoPoints = torsoTypes.compactMap(point)
        if let first = torsoPoints.first {
            let torsoBounds = torsoPoints.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
            rects.append(torsoBounds.insetBy(dx: -8, dy: -8))
        }
        return rects
    }

    private static func quantize(_ value: CGFloat) -> CGFloat {
        (value / 4).rounded() * 4
    }
}
