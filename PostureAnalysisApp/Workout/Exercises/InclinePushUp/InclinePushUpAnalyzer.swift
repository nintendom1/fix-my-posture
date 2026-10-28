import Foundation

/// The incline push-up counts with `PlantedPushUpAnalyzer` (the wall push-up's analyzer) and the incline
/// configuration, which measures the straight-line shoulder-to-wrist distance so it works at any body angle.
final class InclinePushUpAnalyzer: PlantedPushUpAnalyzer {
    override init(epoch: Int, configuration: PlantedPushUpConfiguration = .incline) {
        super.init(epoch: epoch, configuration: configuration)
    }
}
