import Foundation
import CoreGraphics

/// Metadata associated with an imported or captured image.
public struct ImageMetadata: Codable, Hashable {
    public let width: CGFloat
    public let height: CGFloat
    public let dateCaptured: Date
    public let source: ImageSource

    public enum ImageSource: String, Codable {
        case camera
        case photoLibrary
        case synthetic
    }

    public init(width: CGFloat, height: CGFloat, dateCaptured: Date = Date(), source: ImageSource = .photoLibrary) {
        self.width = width
        self.height = height
        self.dateCaptured = dateCaptured
        self.source = source
    }
}
