import Foundation
import UIKit

/// Manages local storage of captured/imported photos in app sandbox container.
public final class ImageStore {
    public static let shared = ImageStore()

    private let fileManager = FileManager.default

    private var imagesDirectoryURL: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("AssessmentImages", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func saveImage(_ image: UIImage, filename: String = "\(UUID().uuidString).jpeg") throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "ImageStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image data."])
        }
        let targetURL = imagesDirectoryURL.appendingPathComponent(filename)
        try data.write(to: targetURL)
        return filename
    }

    public func loadImage(relativePath: String) -> UIImage? {
        let targetURL = imagesDirectoryURL.appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: targetURL.path)
    }

    public func deleteImage(relativePath: String) {
        let targetURL = imagesDirectoryURL.appendingPathComponent(relativePath)
        try? fileManager.removeItem(at: targetURL)
    }
}
