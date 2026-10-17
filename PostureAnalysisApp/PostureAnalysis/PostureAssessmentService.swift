import CoreGraphics
import Foundation

protocol PostureAssessmentService {
    func analyze(
        in image: CGImage,
        metadata: ImageMetadata,
        selectedView: PostureView?,
        horizonContext: HorizonContext?
    ) async throws -> PostureAssessment
}

extension PostureAssessmentService {
    func analyze(in image: CGImage, metadata: ImageMetadata) async throws -> PostureAssessment {
        try await analyze(in: image, metadata: metadata, selectedView: nil, horizonContext: nil)
    }
}

struct LivePostureAssessmentService: PostureAssessmentService {
    private let estimator: any PoseEstimator
    private let analyzer: PostureAnalyzer

    init(estimator: any PoseEstimator, analyzer: PostureAnalyzer = PostureAnalyzer()) {
        self.estimator = estimator
        self.analyzer = analyzer
    }

    func analyze(
        in image: CGImage,
        metadata: ImageMetadata,
        selectedView: PostureView? = nil,
        horizonContext: HorizonContext? = nil
    ) async throws -> PostureAssessment {
        let pose = try await estimator.estimatePose(in: image)
        let view = selectedView ?? ViewClassifier.classify(pose: pose, horizonContext: horizonContext)
        return analyzer.analyze(pose: pose, imageMetadata: metadata, view: view, horizonContext: horizonContext)
    }
}
